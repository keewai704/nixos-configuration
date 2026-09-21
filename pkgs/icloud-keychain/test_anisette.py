import base64
import contextlib
import json
import os
import plistlib
import tempfile
import unittest
from unittest.mock import Mock, patch

import requests

from icp.auth import anisette as a


class AnisetteTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(
            patch.dict(
                os.environ, {"XDG_CONFIG_HOME": self.temp.name, "ICP_ANISETTE_URL": ""}
            )
        )
        self.socket = Mock()
        self.socket.recv.side_effect = [
            json.dumps(message)
            for message in (
                {"result": "GiveIdentifier"},
                {"result": "GiveStartProvisioningData"},
                {"result": "GiveEndProvisioningData", "cpim": a.b64(b"cpim")},
                {
                    "result": "ProvisioningSuccess",
                    "adi_pb": a.b64(b"provisioned-device"),
                },
            )
        ]
        self.connection = self.stack.enter_context(patch.object(a, "connect"))
        self.connection.return_value.__enter__.return_value = self.socket
        self.http = self.stack.enter_context(
            patch.object(a, "request", side_effect=self.reply)
        )
        self.calls = []

    def reply(self, method, url, **kwargs):
        self.calls.append((method, url, kwargs))
        if url == a.LOOKUP:
            self.assertEqual(method, "GET")
            self.assertTrue(kwargs["apple"])
            return plistlib.dumps(
                {
                    "urls": {
                        "midStartProvisioning": "https://gsa.apple.com/start",
                        "midFinishProvisioning": "https://gsa.apple.com/finish",
                    }
                }
            )
        if url.endswith("/start"):
            self.assertEqual(
                plistlib.loads(kwargs["data"]), {"Header": {}, "Request": {}}
            )
            return plistlib.dumps({"Response": {"spim": a.b64(b"spim")}})
        if url.endswith("/finish"):
            self.assertEqual(
                plistlib.loads(kwargs["data"])["Request"], {"cpim": a.b64(b"cpim")}
            )
            self.assertEqual(self.socket.send.call_count, 2)
            return plistlib.dumps(
                {"Response": {"ptm": a.b64(b"ptm"), "tk": a.b64(b"tk")}}
            )
        self.assertTrue(url.endswith("/v3/get_headers"))
        self.assertEqual(set(kwargs), {"json"})
        self.assertEqual(set(kwargs["json"]), {"identifier", "adi_pb"})
        return json.dumps(
            {
                "X-Apple-I-MD": a.b64(b"otp"),
                "X-Apple-I-MD-M": a.b64(b"machine"),
                "X-Apple-I-MD-RINFO": "17106176",
                "Authorization": "must-not-be-forwarded",
            }
        ).encode()

    def test_public_v3_provision_and_reuse(self):
        result = a.Anisette().headers()
        state_path = a.paths.config_dir() / "anisette-v3.json"
        state = json.loads(state_path.read_text())
        self.assertEqual(state_path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(len(base64.b64decode(state["identifier"])), 16)
        self.assertEqual(state["adi_pb"], a.b64(b"provisioned-device"))
        sent = [json.loads(call.args[0]) for call in self.socket.send.call_args_list]
        self.assertEqual(
            sent,
            [
                {"identifier": state["identifier"]},
                {"spim": a.b64(b"spim")},
                {"ptm": a.b64(b"ptm"), "tk": a.b64(b"tk")},
            ],
        )
        self.connection.assert_called_once()
        self.assertEqual(
            self.connection.call_args.args[0],
            "wss://ani.sidestore.io/v3/provisioning_session",
        )
        self.assertIsNone(self.connection.call_args.kwargs["proxy"])
        self.assertNotIn("Authorization", result)
        self.assertEqual(a.Anisette().headers(), result)
        self.assertEqual(len(self.calls), 5)
        self.connection.assert_called_once()

    def test_server_change_never_sends_saved_state(self):
        a.Anisette().headers()
        count = self.http.call_count
        with self.assertRaisesRegex(a.AnisetteError, "another server"):
            a.Anisette("https://different.example").headers()
        self.assertEqual(self.http.call_count, count)

    def test_invalid_state_timeout_and_no_retry(self):
        self.socket.recv.side_effect = TimeoutError("synthetic timeout with secret")
        with self.assertRaises(a.AnisetteError) as error:
            a.Anisette().headers()
        self.assertNotIn("secret", str(error.exception))
        count = self.http.call_count
        with self.assertRaisesRegex(a.AnisetteError, "interrupted"):
            a.Anisette().headers()
        self.assertEqual(self.http.call_count, count)
        self.connection.assert_called_once()

    def test_unexpected_state_and_unsafe_bag(self):
        self.socket.recv.side_effect = [
            json.dumps({"result": "GiveEndProvisioningData", "cpim": a.b64(b"secret")})
        ]
        with self.assertRaises(a.AnisetteError):
            a.Anisette().headers()
        self.socket.send.assert_not_called()

    def test_url_and_blob_validation(self):
        for url in (
            "http://ani.sidestore.io",
            "https://user:password@ani.sidestore.io",
            "https://ani.sidestore.io/?token=x",
            "https://ani.sidestore.io/#x",
            "https://ani.sidestore.io:444",
        ):
            with self.subTest(url=url), self.assertRaises(a.AnisetteError):
                a.Anisette(url)
        for url in (
            "https://apple.com.evil.test/path",
            "https://evilapple.com/path",
            "http://gsa.apple.com/path",
        ):
            with self.subTest(url=url), self.assertRaises(a.AnisetteError):
                a.endpoint(url, apple=True)
        for value in ("", None, "invalid\n", a.b64(b"wrong-size")):
            with self.subTest(value=value), self.assertRaises(a.AnisetteError):
                a.blob(value, size=16)

    def test_unvalidated_state_is_not_sent(self):
        path = a.paths.config_dir() / "anisette-v3.json"
        a.save(
            path,
            {
                "url": a.DEFAULT_ANISETTE_URL,
                "identifier": a.b64(b"x" * 16),
                "adi_pb": "invalid",
            },
        )
        with self.assertRaises(a.AnisetteError):
            a.Anisette().headers()
        self.http.assert_not_called()


class TransportTests(unittest.TestCase):
    def test_verified_tls_no_redirects_and_no_netrc(self):
        with patch.object(a.requests, "Session") as constructor:
            session = constructor.return_value.__enter__.return_value
            response = session.request.return_value.__enter__.return_value
            response.status_code = 200
            response.iter_content.return_value = [b"public ", b"response"]
            self.assertEqual(a.request("GET", a.LOOKUP, apple=True), b"public response")
            self.assertFalse(session.trust_env)
            self.assertEqual(session.request.call_args.kwargs["verify"], a.APPLE_CA)
            self.assertIs(session.request.call_args.kwargs["allow_redirects"], False)
            session.request.assert_called_once()

    def test_redirect_and_oversized_fail_without_retry(self):
        with patch.object(a.requests, "Session") as constructor:
            session = constructor.return_value.__enter__.return_value
            response = session.request.return_value.__enter__.return_value
            response.status_code = 302
            with self.assertRaises(a.AnisetteError):
                a.request("GET", a.LOOKUP, apple=True)
            response.iter_content.assert_not_called()
            session.request.assert_called_once()
            response.status_code = 200
            response.iter_content.return_value = [b"x" * (a.LIMIT + 1)]
            with self.assertRaises(a.AnisetteError):
                a.request("GET", a.LOOKUP, apple=True)

    def test_errors_do_not_disclose_response_or_retry(self):
        with patch.object(a.requests, "Session") as constructor:
            session = constructor.return_value.__enter__.return_value
            session.request.side_effect = requests.RequestException("secret material")
            with self.assertRaises(a.AnisetteError) as error:
                a.request("GET", a.DEFAULT_ANISETTE_URL + "/v3/client_info")
            self.assertNotIn("secret", str(error.exception))
            session.request.assert_called_once()
