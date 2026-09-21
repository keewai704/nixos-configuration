import contextlib
import os
import tempfile
import unittest
from unittest.mock import Mock, patch

from secretstorage.exceptions import ItemNotFoundException

from icp import keyring
from icp.keepassxc import Denied


class KeyringTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.dict(os.environ, XDG_CONFIG_HOME=self.temp.name))
        self.stack.enter_context(
            patch("sys.stdin", Mock(isatty=Mock(return_value=True)))
        )
        self.connection = Mock()
        self.stack.enter_context(
            patch.object(
                keyring.secretstorage, "dbus_init", return_value=self.connection
            )
        )
        self.collection = Mock(collection_path="/synthetic/keyring")
        self.collection.is_locked.side_effect = [True, False]
        self.constructor = self.stack.enter_context(
            patch.object(
                keyring.secretstorage, "Collection", return_value=self.collection
            )
        )
        self.prompt = self.stack.enter_context(
            patch.object(keyring.getpass, "getpass", return_value="synthetic-password")
        )
        self.session = self.stack.enter_context(
            patch.object(keyring, "open_session", return_value=Mock(encrypted=True))
        )
        self.formatter = self.stack.enter_context(
            patch.object(keyring, "format_secret", return_value=("encrypted",))
        )
        self.address = self.stack.enter_context(
            patch.object(keyring, "DBusAddressWrapper")
        )
        self.address.return_value.call.return_value = ("/synthetic/keyring",)

    def test_unlock_uses_encrypted_session_and_never_gui_prompt(self):
        keyring.unlock()
        self.collection.unlock.assert_not_called()
        self.address.return_value.call.assert_called_once_with(
            "UnlockWithMasterPassword",
            "o(oayays)",
            "/synthetic/keyring",
            ("encrypted",),
        )
        self.connection.close.assert_called_once()

    def test_new_keyring_requires_confirmation_and_default_alias(self):
        self.constructor.side_effect = [
            ItemNotFoundException("missing"),
            Mock(is_locked=Mock(return_value=False)),
        ]
        keyring.unlock()
        self.assertEqual(self.prompt.call_count, 2)
        calls = self.address.return_value.call.call_args_list
        self.assertEqual(calls[0].args[0], "CreateWithMasterPassword")
        self.assertEqual(
            calls[1].args, ("SetAlias", "so", "default", "/synthetic/keyring")
        )

    def test_mismatch_blank_or_plain_transport_fail_closed(self):
        self.prompt.return_value = ""
        with self.assertRaises(Denied):
            keyring.unlock()
        self.address.assert_not_called()
        self.collection.is_locked.side_effect = None
        self.collection.is_locked.return_value = True
        self.prompt.return_value = "synthetic-password"
        self.session.return_value.encrypted = False
        with self.assertRaises(Denied):
            keyring.unlock()
        self.formatter.assert_not_called()

    def test_missing_keyring_does_not_replace_existing_account_key(self):
        keyring.paths.vault_file().write_bytes(b"synthetic-encrypted-data")
        self.constructor.side_effect = ItemNotFoundException("missing")
        with self.assertRaises(Denied):
            keyring.unlock()
        self.prompt.assert_not_called()
        self.address.assert_not_called()

    def test_noninteractive_unlock_is_rejected(self):
        with (
            patch("sys.stdin", Mock(isatty=Mock(return_value=False))),
            self.assertRaises(Denied),
        ):
            keyring.unlock()
        self.prompt.assert_not_called()
