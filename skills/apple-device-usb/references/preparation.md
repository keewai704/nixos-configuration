# Device preparation

Preparation is separate from control. Follow the skill's host, authorization,
privacy, and exclusive-use boundaries before these operations.

## Select a USB device

```sh
systemctl is-active usbmuxd
timeout -k 3 20 pymobiledevice3 usbmux list --usb --simple
```

This lists USB UDIDs without opening lockdown connections. For USB control or
preparation, stop if none are present; ask which device when ambiguous. Already
paired Wi-Fi control does not require an attached USB device. Keep identifiers
and personal device names out of external diagnostics.

## Trust, Developer Mode, and developer images

Before changing trust, revealing Developer Mode, or downloading/mounting an image,
explain the effect and obtain authorization unless already given. Developer Mode
permits developer-service access from trusted computers. The user enters
passcodes, approves Trust, enables Developer Mode, and confirms restarts on-device.
Do not automate these confirmations; preserve pairing records.

With the selected device already trusted and unlocked, check its state:

```sh
PYMOBILEDEVICE3_UDID='<observed-UDID>' pymobiledevice3 amfi developer-mode-status
PYMOBILEDEVICE3_UDID='<observed-UDID>' pymobiledevice3 mounter list
```

If Developer Mode is off, explain Settings → Privacy & Security → Developer
Mode. Use `amfi reveal-developer-mode` only when needed and authorized, with the
same UDID selection. Wait for the user's enable/restart/confirmation, then check
again. Do not force the USB path on versions older than 17.4; inspect the installed
`pymobiledevice3 --help` and upstream transport guidance. Wi-Fi still requires
compatible display and input services, regardless of OS version.

Mount only when no developer image is mounted and the operation is authorized:

```sh
PYMOBILEDEVICE3_UDID='<observed-UDID>' pymobiledevice3 mounter auto-mount
```

Allow the initial download to finish. Check again after a reboot; do not mount
on every connection, unmount an existing image, or replace one as automatic
recovery. Close an existing controller before any image-changing operation.

## Optional Wi-Fi pairing

USB trust and CoreDevice Wi-Fi pairing are separate. If wireless control is
requested and no matching record exists, explain that pairing creates a saved
network credential and obtain authorization. With the same device trusted,
unlocked, and connected over USB, run once:

```sh
PYMOBILEDEVICE3_UDID='<observed-UDID>' pymobiledevice3 lockdown remotepairing --pair
```

Do not read pairing keys, delete records, or repeat pairing automatically. Reuse
an existing record; the helper connects with automatic pairing disabled.
Keep the device and this host on the same local network. For a wireless check,
close the USB session, have the user disconnect the cable, and start with
`--connection wifi`. Discovery with `pymobiledevice3 remote browse` is optional;
its identifiers and addresses must stay local. The helper rejects loopback,
known tunnel interfaces, and `ipheth` USB tethering routes. Do not change firewall
or route settings to bypass a failed check.
