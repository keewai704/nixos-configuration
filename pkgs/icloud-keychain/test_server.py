import contextlib
import hashlib
import io
import json
import os
import socket
import ssl
import tempfile
import threading
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import Mock, patch

from websockets.datastructures import Headers
from websockets.sync.client import connect
from websockets.sync.server import serve
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

from icp import server
from icp import keepassxc as bridge
from icp.keepassxc import Denied
from test_keepassxc import Client


class Connection:
    def __init__(self, messages=()):
        self.messages = iter(messages)
        self.sent = []
        self.closed = None
        self.socket = Mock()

    def __iter__(self):
        return self.messages

    def respond(self, code, body):
        return code, body

    def send(self, message):
        self.sent.append(json.loads(message))

    def close(self, code, reason):
        self.closed = code, reason


class ServerTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.environment = patch.dict(os.environ, XDG_CONFIG_HOME=self.directory.name)
        self.environment.start()
        self.addCleanup(self.environment.stop)
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            server.manage_client("client-add", "browser")
        self.token = output.getvalue().strip()
        self.server = server.Server("https://orange.example/icloud-keychain/")

    def request(self, **overrides):
        values = {"Host": "orange.example", "Authorization": "Bearer " + self.token}
        values.update(overrides)
        return Mock(path="/icloud-keychain/", headers=Headers(values))

    def test_authorization_is_private_hashed_and_explicit(self):
        path = server.paths.config_dir() / "clients.json"
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertNotIn(self.token, path.read_text())
        self.assertEqual(
            server.load_clients()["browser"],
            hashlib.sha256(self.token.encode()).hexdigest(),
        )
        with self.assertRaises(Denied):
            server.manage_client("client-add", "browser")
        with contextlib.redirect_stdout(io.StringIO()) as output:
            server.manage_client("client-list")
        self.assertEqual(output.getvalue(), "browser\n")

    def test_handshake_checks_path_host_origin_and_token(self):
        connection = Connection()
        self.assertIsNone(self.server.process_request(connection, self.request()))
        self.assertTrue(server.authorized(connection.icloud_digest))
        for request, status in (
            (self.request(Authorization=""), 401),
            (self.request(Authorization="Bearer " + "A" * 43), 401),
            (self.request(Host="evil.example"), 404),
            (self.request(Origin="https://orange.example"), 403),
            (
                Mock(path="/icloud-keychain/?token=x", headers=self.request().headers),
                404,
            ),
        ):
            self.assertEqual(
                self.server.process_request(Connection(), request)[0], status
            )

    def test_duplicate_sensitive_headers_fail_closed(self):
        request = self.request()
        request.headers["Authorization"] = "Bearer " + self.token
        self.assertEqual(self.server.process_request(Connection(), request)[0], 401)

    def test_connections_have_independent_protocols(self):
        connections = [Connection(['{"action":"test"}']) for _ in range(2)]
        for connection in connections:
            self.assertIsNone(self.server.process_request(connection, self.request()))
        protocols = [Mock(), Mock()]
        for protocol in protocols:
            protocol.handle.return_value = {"action": "test", "message": "opaque"}
        with patch.object(server, "Protocol", side_effect=protocols) as factory:
            for connection in connections:
                self.server.handle(connection)
            self.assertEqual(factory.call_count, 2)
            self.assertTrue(factory.call_args.kwargs["approve_association"]("key"))
        for protocol in protocols:
            protocol.handle.assert_called_once_with({"action": "test"})

    def test_revocation_blocks_existing_connection_before_read(self):
        connection = Connection(['{"action":"get-logins"}'])
        self.assertIsNone(self.server.process_request(connection, self.request()))
        server.manage_client("client-revoke", "browser")
        with patch.object(server, "Protocol") as factory:
            self.server.handle(connection)
            factory.return_value.handle.assert_not_called()
        self.assertEqual(connection.closed[0], 1008)
        self.assertFalse(connection.sent)

    def test_logout_revokes_clients_before_another_account_can_sign_in(self):
        self.assertEqual(bridge.main(["logout"]), 0)
        self.assertEqual(server.load_clients(), {})
        self.assertEqual(
            self.server.process_request(Connection(), self.request())[0], 401
        )

    def test_revocation_during_request_blocks_response(self):
        connection = Connection(['{"action":"get-logins"}'])
        self.server.process_request(connection, self.request())

        def revoke(payload):
            server.manage_client("client-revoke", "browser")
            return {"action": "get-logins", "message": "synthetic-secret"}

        with patch.object(server, "Protocol") as factory:
            factory.return_value.handle.side_effect = revoke
            self.server.handle(connection)
        self.assertFalse(connection.sent)
        self.assertEqual(connection.closed[0], 1008)

    def test_malformed_messages_are_not_logged_or_retried(self):
        for message in ("not JSON", "[]", b"binary", "x" * (server.MAX_MESSAGE + 1)):
            connection = Connection([message])
            self.server.process_request(connection, self.request())
            self.server.handle(connection)
            self.assertIsNotNone(connection.closed)
            self.assertFalse(connection.sent)

    def test_listener_is_loopback_and_bounded(self):
        with patch.object(server, "serve") as listener:
            server.run_server("https://orange.example/icloud-keychain/", 30142)
        self.assertEqual(listener.call_args.args[1:], ("127.0.0.1", 30142))
        self.assertEqual(listener.call_args.kwargs["origins"], [None])
        self.assertEqual(listener.call_args.kwargs["max_size"], server.MAX_MESSAGE)
        with self.assertRaises(ValueError):
            server.run_server("https://orange.example/icloud-keychain/", 0)

    def test_unsafe_public_urls_are_rejected(self):
        for value in (
            "http://orange.example/icloud-keychain/",
            "https://a:b@orange.example/icloud-keychain/",
            "https://orange.example:8443/icloud-keychain/",
            "https://orange.example/other/",
        ):
            with self.assertRaises(ValueError):
                server.Server(value)

    def test_verified_tls_and_encrypted_credentials(self):
        directory = Path(self.directory.name)
        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "orange.example")])
        certificate = (
            x509.CertificateBuilder()
            .subject_name(subject)
            .issuer_name(subject)
            .public_key(key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(datetime.now(timezone.utc) - timedelta(minutes=1))
            .not_valid_after(datetime.now(timezone.utc) + timedelta(days=1))
            .add_extension(
                x509.SubjectAlternativeName([x509.DNSName("orange.example")]),
                critical=False,
            )
            .add_extension(
                x509.BasicConstraints(ca=True, path_length=None), critical=True
            )
            .sign(key, hashes.SHA256())
        )
        cert_path = directory / "test-cert.pem"
        key_path = directory / "test-key.pem"
        cert_path.write_bytes(certificate.public_bytes(serialization.Encoding.PEM))
        key_path.write_bytes(
            key.private_bytes(
                serialization.Encoding.PEM,
                serialization.PrivateFormat.PKCS8,
                serialization.NoEncryption(),
            )
        )
        key_path.chmod(0o600)
        tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        tls.load_cert_chain(cert_path, key_path)
        trusted = ssl.create_default_context(cafile=str(cert_path))
        credentials = [
            {
                "domain": "example.com",
                "username": "synthetic",
                "password": "synthetic-secret",
            }
        ]
        with (
            patch.object(bridge, "load_credentials", return_value=credentials),
            serve(
                self.server.handle,
                "127.0.0.1",
                0,
                ssl=tls,
                process_request=self.server.process_request,
                origins=[None],
                max_size=server.MAX_MESSAGE,
            ) as listener,
        ):
            thread = threading.Thread(target=listener.serve_forever, daemon=True)
            thread.start()
            port = listener.socket.getsockname()[1]

            def local_connect(url, **kwargs):
                return connect(
                    url,
                    sock=socket.create_connection(("127.0.0.1", port), timeout=5),
                    **kwargs,
                )

            try:
                with local_connect(
                    "wss://orange.example/icloud-keychain/",
                    ssl=trusted,
                    proxy=None,
                    additional_headers={"Authorization": "Bearer " + self.token},
                    open_timeout=5,
                    close_timeout=2,
                ) as connection:

                    class Remote:
                        def handle(self, request):
                            connection.send(json.dumps(request))
                            return json.loads(connection.recv(timeout=5))

                    client = Client(Remote())
                    client.associate()
                    self.assertEqual(
                        client.logins()["entries"][0]["password"], "synthetic-secret"
                    )
            finally:
                listener.shutdown()
                thread.join(timeout=5)
                self.assertFalse(thread.is_alive())
