import contextlib
import importlib.util
import io
import os
import secrets
import ssl
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

try:
    import icloud_keychain_client as client
except ModuleNotFoundError as error:
    if error.name != "icloud_keychain_client":
        raise
    spec = importlib.util.spec_from_file_location(
        "icloud_keychain_client", Path(__file__).with_name("client.py")
    )
    client = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(client)


class Socket:
    def __init__(self, replies):
        self.replies = iter(replies)
        self.sent = []
        self.closed = False
        self.socket = Mock()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.closed = True

    def send(self, message):
        self.sent.append(message)

    def recv(self, timeout):
        assert timeout == client.RECEIVE_TIMEOUT
        reply = next(self.replies)
        if isinstance(reply, Exception):
            raise reply
        return reply


def frame(value):
    encoded = value.encode()
    return client.HEADER.pack(len(encoded)) + encoded


class ClientTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(
            patch.dict(os.environ, XDG_CONFIG_HOME=self.directory.name)
        )
        self.stack.enter_context(
            patch.object(
                client, "DEFAULT_SERVER_URL", "wss://orange.example/icloud-keychain/"
            )
        )
        self.token = secrets.token_urlsafe(32)

    def test_token_is_private_and_status_never_prints_it(self):
        client.save_token(self.token)
        self.assertEqual(client.load_token(), self.token)
        self.assertEqual(client.token_path().stat().st_mode & 0o777, 0o600)
        self.assertEqual(client.config_directory().stat().st_mode & 0o777, 0o700)
        with contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(client.status(), 0)
        self.assertEqual(output.getvalue(), "configured\n")

    def test_insecure_token_file_is_rejected(self):
        client.save_token(self.token)
        client.token_path().chmod(0o644)
        self.assertIsNone(client.load_token())
        other = Path(self.directory.name) / "other"
        client.token_path().rename(other)
        client.token_path().symlink_to(other)
        self.assertIsNone(client.load_token())

    def test_configure_is_interactive_and_non_echoing(self):
        with (
            patch("sys.stdin", Mock(isatty=Mock(return_value=True))),
            patch.object(client.getpass, "getpass", return_value=self.token),
            contextlib.redirect_stdout(io.StringIO()) as output,
        ):
            self.assertEqual(client.configure(), 0)
        self.assertNotIn(self.token, output.getvalue())
        with (
            patch("sys.stdin", Mock(isatty=Mock(return_value=False))),
            patch.object(client.getpass, "getpass") as prompt,
            contextlib.redirect_stderr(io.StringIO()),
        ):
            self.assertEqual(client.configure(), 1)
            prompt.assert_not_called()

    def test_invalid_tokens_are_not_saved_or_logged(self):
        for value in ("", "short", "A" * 42, "A" * 44, "!" * 43):
            with (
                patch("sys.stdin", Mock(isatty=Mock(return_value=True))),
                patch.object(client.getpass, "getpass", return_value=value),
                contextlib.redirect_stderr(io.StringIO()) as error,
            ):
                self.assertEqual(client.configure(), 1)
            if value:
                self.assertNotIn(value, error.getvalue())
            self.assertIsNone(client.load_token())

    def test_only_canonical_verified_wss_url_is_allowed(self):
        for value in (
            "ws://orange.example/icloud-keychain/",
            "wss://a:b@orange.example/icloud-keychain/",
            "wss://orange.example:8443/icloud-keychain/",
            "wss://orange.example/other/",
            "wss://orange.example/icloud-keychain/?token=x",
            "wss://orange.example/icloud-keychain/#fragment",
        ):
            with self.assertRaises(ValueError):
                client.validate_server_url(value)

    def test_relay_preserves_json_and_ciphertext(self):
        request = (
            '{"action":"change-public-keys", "publicKey":"opaque","nonce":"opaque"}'
        )
        response = '{"action":"change-public-keys","publicKey":"server-opaque"}'
        socket = Socket([response])
        output = io.BytesIO()
        with patch.object(client, "connect", return_value=socket) as connect:
            self.assertEqual(
                client.relay(io.BytesIO(frame(request)), output, self.token), 0
            )
        self.assertEqual(socket.sent, [request])
        self.assertEqual(output.getvalue(), frame(response))
        self.assertTrue(socket.closed)
        connect.assert_called_once()
        options = connect.call_args.kwargs
        self.assertEqual(
            options["additional_headers"], {"Authorization": "Bearer " + self.token}
        )
        self.assertIsNone(options["proxy"])
        self.assertTrue(options["ssl"].check_hostname)
        self.assertEqual(options["ssl"].verify_mode, ssl.CERT_REQUIRED)

    def test_eof_closes_socket_without_output(self):
        socket = Socket([])
        output = io.BytesIO()
        with patch.object(client, "connect", return_value=socket):
            self.assertEqual(client.relay(io.BytesIO(), output, self.token), 0)
        self.assertTrue(socket.closed)
        self.assertEqual(output.getvalue(), b"")

    def test_remote_close_ends_idle_native_input(self):
        read_fd, write_fd = os.pipe()
        connection = Mock(state=client.State.CLOSED)
        try:
            with os.fdopen(read_fd, "rb", buffering=0) as stream:
                self.assertEqual(client.NativeInput(stream, connection).read(1), b"")
        finally:
            os.close(write_fd)

    def test_remote_close_interrupts_a_partial_native_frame(self):
        read_fd, write_fd = os.pipe()
        os.write(write_fd, b"\x01")
        connection = Mock(state=client.State.OPEN)
        timer = threading.Timer(
            0.05, lambda: setattr(connection, "state", client.State.CLOSED)
        )
        timer.start()
        try:
            with (
                os.fdopen(read_fd, "rb", buffering=0) as stream,
                self.assertRaises(ValueError),
            ):
                client.read_frame(client.NativeInput(stream, connection))
        finally:
            timer.join(timeout=1)
            os.close(write_fd)

    def test_invalid_frames_and_responses_are_rejected(self):
        for value in (
            b"\x01",
            client.HEADER.pack(0),
            client.HEADER.pack(client.MAX_MESSAGE + 1),
            client.HEADER.pack(2) + b"{",
            frame("[]"),
            frame('{"value":NaN}'),
        ):
            with self.assertRaises((ValueError, TypeError)):
                client.read_frame(io.BytesIO(value))
        for value in (b"binary", "[]", "x" * (client.MAX_MESSAGE + 1)):
            with self.assertRaises((ValueError, TypeError)):
                client.response_frame(value)

    def test_fragmented_header_and_body_are_supported(self):
        class Fragmented(io.BytesIO):
            def read(self, size):
                return super().read(min(size, 1))

        self.assertEqual(
            client.read_frame(Fragmented(frame('{"test":true}'))), '{"test":true}'
        )

    def test_failed_request_is_never_retried_or_logged(self):
        client.save_token(self.token)
        socket = Socket([TimeoutError(self.token)])
        output = io.BytesIO()
        with (
            patch.object(client, "connect", return_value=socket) as connect,
            contextlib.redirect_stderr(io.StringIO()) as error,
        ):
            self.assertEqual(
                client.native_host(
                    io.BytesIO(frame('{"action":"get-logins"}')), output
                ),
                1,
            )
        connect.assert_called_once()
        self.assertEqual(len(socket.sent), 1)
        self.assertTrue(socket.closed)
        self.assertNotIn(self.token, error.getvalue())
        self.assertFalse(output.getvalue())

    def test_browser_arguments_do_not_change_native_mode(self):
        with patch.object(client, "native_host", return_value=7) as native:
            self.assertEqual(
                client.main(["native-host", "browser-origin", "--configure"]), 7
            )
        native.assert_called_once_with()
