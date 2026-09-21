import getpass
import sys

import secretstorage
from secretstorage.exceptions import ItemNotFoundException
from secretstorage.util import DBusAddressWrapper, format_secret, open_session

from . import paths
from .keepassxc import Denied


def unlock():
    if not sys.stdin.isatty():
        raise Denied(6, "Keyring unlock requires an interactive terminal on Orange")
    connection = secretstorage.dbus_init()
    try:
        try:
            collection = secretstorage.Collection(connection)
        except ItemNotFoundException:
            collection = None
        if collection is not None and not collection.is_locked():
            return
        if collection is None and any(
            (paths.config_dir() / name).exists()
            for name in ("session.enc", "vault.enc", "aliases.enc")
        ):
            raise Denied(
                1,
                "Default keyring is missing; existing encrypted account data was not changed",
            )
        password = getpass.getpass("Server keyring password (not the Apple password): ")
        if not password:
            raise Denied(6, "An empty keyring password is not permitted")
        if collection is None and password != getpass.getpass(
            "Confirm new keyring password: "
        ):
            raise Denied(6, "Keyring passwords did not match")
        session = open_session(connection)
        if not session.encrypted:
            raise Denied(6, "Encrypted Secret Service transport is required")
        secret = format_secret(session, password.encode(), "text/plain")
        internal = DBusAddressWrapper(
            "/org/freedesktop/secrets",
            "org.gnome.keyring.InternalUnsupportedGuiltRiddenInterface",
            connection,
        )
        if collection is None:
            (path,) = internal.call(
                "CreateWithMasterPassword",
                "a{sv}(oayays)",
                {"org.freedesktop.Secret.Collection.Label": ("s", "iCloud Keychain")},
                secret,
            )
            service = DBusAddressWrapper(
                "/org/freedesktop/secrets", "org.freedesktop.Secret.Service", connection
            )
            service.call("SetAlias", "so", "default", path)
        else:
            internal.call(
                "UnlockWithMasterPassword",
                "o(oayays)",
                collection.collection_path,
                secret,
            )
        if secretstorage.Collection(connection).is_locked():
            raise Denied(1, "Keyring remains locked; no retry was made")
    finally:
        connection.close()
