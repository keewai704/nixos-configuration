import contextlib
import json
import os
import secrets
import tempfile
import unittest
from unittest.mock import Mock, patch

import nacl.public

from icp import keepassxc as bridge


class Client:
    def __init__(self, server):
        self.server = server
        self.key = nacl.public.PrivateKey.generate()
        self.identifier = bridge.encode(secrets.token_bytes(24))
        self.identification_key = bridge.encode(
            bytes(nacl.public.PrivateKey.generate().public_key)
        )
        nonce = secrets.token_bytes(24)
        response = server.handle(
            {
                "action": "change-public-keys",
                "clientID": self.identifier,
                "nonce": bridge.encode(nonce),
                "publicKey": bridge.encode(bytes(self.key.public_key)),
            }
        )
        expected = ((int.from_bytes(nonce, "little") + 1) % (1 << 192)).to_bytes(
            24, "little"
        )
        assert response["nonce"] == bridge.encode(expected)
        assert response["success"] == "true"
        self.box = nacl.public.Box(
            self.key, nacl.public.PublicKey(bridge.decode(response["publicKey"]))
        )
        self.association = None

    def request(self, action, **data):
        nonce = secrets.token_bytes(24)
        payload = json.dumps({"action": action, **data}).encode()
        return {
            "action": action,
            "clientID": self.identifier,
            "nonce": bridge.encode(nonce),
            "message": bridge.encode(self.box.encrypt(payload, nonce).ciphertext),
        }

    def send(self, action, **data):
        request = self.request(action, **data)
        response = self.server.handle(request)
        if "errorCode" in response:
            return response
        expected = (
            (int.from_bytes(bridge.decode(request["nonce"]), "little") + 1) % (1 << 192)
        ).to_bytes(24, "little")
        assert response["nonce"] == bridge.encode(expected)
        result = json.loads(
            self.box.decrypt(bridge.decode(response["message"]), expected)
        )
        assert result["nonce"] == response["nonce"]
        assert result["success"] == "true"
        return result

    def associate(self):
        result = self.send(
            "associate",
            key=bridge.encode(bytes(self.key.public_key)),
            idKey=self.identification_key,
        )
        self.association = {"id": result["id"], "key": self.identification_key}
        return result

    def logins(self, url="https://example.com/login", **data):
        return self.send("get-logins", url=url, keys=[self.association], **data)


class ProtocolTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.dict(os.environ, XDG_CONFIG_HOME=self.temp.name))
        self.credentials = [
            {
                "domain": "example.com",
                "username": "alice",
                "password": "synthetic-secret",
                "title": "Example",
                "totp": "otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP",
            },
            {"domain": "other.test", "username": "bob", "password": "other-secret"},
        ]
        self.loader = self.stack.enter_context(
            patch.object(bridge, "load_credentials", return_value=self.credentials)
        )
        self.approval = Mock(return_value=True)
        self.server = bridge.Protocol(approve_association=self.approval)
        self.client = Client(self.server)

    def test_pair_reconnect_and_fill(self):
        database = self.client.send("get-databasehash")
        paired = self.client.associate()
        self.assertEqual(database["hash"], paired["hash"])
        association = self.client.association
        client = Client(bridge.Protocol())
        client.association = association
        self.assertEqual(
            client.send("test-associate", **association)["id"], association["id"]
        )
        result = client.logins()
        self.assertEqual(result["count"], "1")
        self.assertEqual(result["entries"][0]["password"], "synthetic-secret")
        self.assertEqual(len(result["entries"][0]["totp"]), 6)
        self.assertNotIn("JBSWY3DPEHPK3PXP", json.dumps(result))
        self.assertNotIn("other-secret", json.dumps(result))

    def test_totp_survives_browser_test_associate(self):
        self.client.associate()
        entry = self.client.logins()["entries"][0]
        self.client.send("get-databasehash")
        self.client.send("test-associate", **self.client.association)
        self.assertEqual(
            len(self.client.send("get-totp", uuid=entry["uuid"])["totp"]), 6
        )
        self.assertEqual(
            self.client.send("get-totp", uuid=bridge.entry_id(self.credentials[1]))[
                "errorCode"
            ],
            18,
        )

    def test_consent_and_keys_are_required(self):
        self.assertEqual(self.client.logins()["errorCode"], 10)
        self.approval.return_value = False
        result = self.client.send(
            "associate",
            key=bridge.encode(bytes(self.client.key.public_key)),
            idKey=self.client.identification_key,
        )
        self.assertEqual(result["errorCode"], 6)
        self.approval.return_value = True
        self.client.associate()
        wrong = dict(
            self.client.association, key=bridge.encode(secrets.token_bytes(32))
        )
        self.assertEqual(self.client.send("test-associate", **wrong)["errorCode"], 10)
        self.assertEqual(
            self.client.send("get-totp", uuid=bridge.entry_id(self.credentials[0]))[
                "errorCode"
            ],
            10,
        )

    def test_revocation_and_cross_session(self):
        self.client.associate()
        self.client.logins()
        other = Client(bridge.Protocol())
        self.assertEqual(
            other.send("get-totp", uuid=bridge.entry_id(self.credentials[0]))[
                "errorCode"
            ],
            10,
        )
        with bridge.associations() as state:
            state["keys"].clear()
        self.assertEqual(self.client.logins()["errorCode"], 10)

    def test_origin_boundaries(self):
        self.client.associate()
        for url in (
            "https://notexample.com",
            "https://example.com.evil.test",
            "https://login.example.com",
            "https://example.com:444",
            "https://example.com:0",
            "https://example.com./",
        ):
            with self.subTest(url=url):
                self.assertEqual(self.client.logins(url)["entries"], [])
        for url in (
            "http://example.com",
            "javascript:alert(1)",
            "https://alice@example.com",
            "https://example.com\\evil.test",
        ):
            with self.subTest(url=url):
                self.assertEqual(self.client.logins(url)["errorCode"], 14)
        self.assertEqual(
            self.client.logins(submitUrl="https://evil.test")["errorCode"], 14
        )
        self.assertEqual(self.client.logins("https://EXAMPLE.com:443/")["count"], "1")

    def test_replay_tampering_and_read_only(self):
        self.client.associate()
        request = self.client.request(
            "get-logins", url="https://example.com", keys=[self.client.association]
        )
        self.assertIn("message", self.server.handle(request))
        self.assertEqual(self.server.handle(request)["errorCode"], 4)
        request = self.client.request("get-databasehash")
        request["action"] = "get-logins"
        self.assertEqual(self.server.handle(request)["errorCode"], 4)
        request = self.client.request("get-databasehash")
        request["message"] = bridge.encode(secrets.token_bytes(64))
        self.assertEqual(self.server.handle(request)["errorCode"], 4)
        for action in (
            "set-login",
            "create-new-group",
            "passkeys-get",
            "passkeys-register",
        ):
            self.assertEqual(self.client.send(action)["errorCode"], 6)

    def test_lock_is_global(self):
        self.client.associate()
        self.assertEqual(self.client.send("lock-database")["errorCode"], 1)
        self.assertTrue(bridge.lock_path().exists())
        self.assertIsNone(self.server.authorized)


class StorageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.dict(os.environ, XDG_CONFIG_HOME=self.temp.name))
        self.stack.enter_context(
            patch.object(bridge.secretstorage, "dbus_init", return_value=Mock())
        )
        self.collection = Mock()
        self.collection.is_locked.return_value = False
        self.collection.search_items.return_value = []
        self.stack.enter_context(
            patch.object(
                bridge.secretstorage,
                "Collection",
                return_value=self.collection,
            )
        )

    def test_locked_keyring_never_unlocks_for_browser(self):
        self.collection.is_locked.return_value = True
        with self.assertRaises(bridge.Denied):
            bridge.master_key()
        self.collection.unlock.assert_not_called()
        self.assertFalse(bridge.paths.fallback_key_file().exists())

    def test_missing_or_invalid_key_never_replaces_existing_data(self):
        bridge.paths.vault_file().write_bytes(b"encrypted synthetic vault")
        with self.assertRaises(bridge.Denied):
            bridge.master_key(interactive=True)
        self.collection.create_item.assert_not_called()
        self.assertEqual(
            bridge.paths.vault_file().read_bytes(), b"encrypted synthetic vault"
        )
        self.collection.search_items.return_value = [
            Mock(get_secret=Mock(return_value=b"invalid"))
        ]
        with self.assertRaises(bridge.Denied):
            bridge.master_key(interactive=True)
        self.collection.create_item.assert_not_called()

    def test_new_key_is_created_only_for_interactive_cli(self):
        with self.assertRaises(bridge.Denied):
            bridge.master_key()
        key = bridge.master_key(interactive=True)
        self.assertEqual(len(key), 32)
        self.assertEqual(
            self.collection.create_item.call_args.kwargs, {"replace": False}
        )
        self.assertIsInstance(self.collection.create_item.call_args.args[2], bytes)
        self.assertFalse(bridge.paths.fallback_key_file().exists())

    def test_corrupt_vault_is_not_deleted(self):
        bridge.paths.session_file().write_bytes(b"synthetic session")
        bridge.paths.vault_file().write_bytes(b"corrupt synthetic vault")
        with patch.object(bridge, "master_key", return_value=secrets.token_bytes(32)):
            with self.assertRaises(bridge.Denied):
                bridge.load_credentials()
        self.assertEqual(
            bridge.paths.vault_file().read_bytes(), b"corrupt synthetic vault"
        )

    def test_private_atomic_state_and_logout(self):
        with bridge.associations() as state:
            state["keys"]["test"] = "synthetic"
        path = bridge.paths.config_dir() / "keepassxc.json"
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        for name in ("session.enc", "vault.enc", "aliases.enc", "device.json"):
            (path.parent / name).write_bytes(b"synthetic")
        self.assertEqual(bridge.main(["logout"]), 0)
        self.assertEqual(json.loads(path.read_text())["keys"], {})
        self.assertTrue((path.parent / "device.json").exists())
        self.assertTrue(bridge.lock_path().exists())
        self.assertFalse(bridge.paths.vault_file().exists())
