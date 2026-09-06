# Bitwarden on citrus

The desktop app uses the existing GNOME Secret Service and polkit agent for
system authentication. Enable **Unlock with system authentication** in the
Bitwarden settings after signing in. Linux requires the first vault unlock
after each app restart before system authentication can unlock it again.

Enable **SSH agent** in the desktop settings. SSH uses
`~/.bitwarden-ssh-agent.sock`; GNOME's competing SSH agent is disabled.
Keep the default request authorization policy. Add SSH-key items to the vault
in Bitwarden; private keys do not belong in this repository.
The desktop app starts at login using its own writable autostart file.

## Launcher

Open Apps and choose **Bitwarden**, or type `bw ` followed by an item name,
username, folder, or URL. Choose **Set up** once and enter the account email
locally. Passwords and verification codes are requested by pinentry.
The configured server is `https://orange.tail1e65cd.ts.net/vault`.

The launcher uses `rbw`, which has a separate login and unlock session from the
desktop app. Its account configuration remains writable under `~/.config/rbw/`;
no account credentials or session tokens are stored in Nix. The vault locks
after 300 seconds of inactivity. Use **Unlock**, **Lock**, and **Sync** as needed.

Select a login item with Up/Down or a click:

| Shortcut | Copy |
| --- | --- |
| Ctrl+C | Username |
| Ctrl+Shift+C | Password |
| Ctrl+Alt+C | One-time code |
| Enter | Password |

Copies are marked sensitive to exclude them from compatible clipboard history
managers. The selection expires after 30 seconds; expiry of an older copy does
not clear a newer clipboard selection. Passwords and one-time codes are passed
directly to the clipboard helper, never returned to the QML UI or its logs.
Items with identical names are selected by their vault UUID.

## Checks

In `/home/keewai/dynamic-island`, run `nix flake check` for the package and
backend checks. The dedicated Bitwarden UI and clipboard checks use dummy
items in a private headless Wayland compositor, without a real account.
