{
  inputs,
  pkgs,
  mkProxyLocation,
  ...
}:
let
  inherit (import ../settings.nix) pondPort tailnetHostname tailnetOrigin;
  qemu = pkgs.qemu_kvm;
in
{
  systemd.services.pond-vm = {
    description = "Pond trial virtual machine";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [ qemu ];
    preStart = ''
      if [[ ! -e disk.qcow2 ]]; then
        qemu-img create -f qcow2 disk.qcow2 24G
      fi
      if [[ ! -e OVMF_VARS.fd ]]; then
        install -m 600 ${pkgs.OVMF.fd}/FV/OVMF_VARS.fd OVMF_VARS.fd
      fi
    '';
    script = ''
      exec qemu-system-x86_64 \
        -name pond \
        -machine q35,accel=kvm \
        -cpu host -smp 2 -m 2048 \
        -drive if=pflash,format=raw,readonly=on,file=${pkgs.OVMF.fd}/FV/OVMF_CODE.fd \
        -drive if=pflash,format=raw,file=OVMF_VARS.fd \
        -drive if=virtio,format=qcow2,file=disk.qcow2,discard=unmap \
        -drive media=cdrom,format=raw,readonly=on,file=${inputs.pond-iso} \
        -boot order=cd,menu=on \
        -device virtio-vga-gl \
        -display egl-headless,rendernode=/dev/dri/renderD128 \
        -vnc unix:/run/pond/vnc.sock,websocket=127.0.0.1:${toString pondPort} \
        -monitor unix:/run/pond/monitor.sock,server=on,wait=off \
        -serial null \
        -device qemu-xhci -device usb-tablet \
        -device virtio-rng-pci \
        -nic user,model=virtio-net-pci,hostname=pond
    '';
    preStop = ''
      if [[ -S /run/pond/monitor.sock ]]; then
        printf 'system_powerdown\n' | ${pkgs.socat}/bin/socat -T 1 - UNIX-CONNECT:/run/pond/monitor.sock || true
        for _attempt in {1..60}; do
          kill -0 "$MAINPID" 2>/dev/null || exit 0
          sleep 1
        done
      fi
    '';
    serviceConfig = {
      DynamicUser = true;
      SupplementaryGroups = [
        "kvm"
        "render"
      ];
      StateDirectory = "pond";
      RuntimeDirectory = "pond";
      WorkingDirectory = "/var/lib/pond";
      UMask = "0077";
      Restart = "on-failure";
      RestartSec = 5;
      TimeoutStopSec = 90;
      MemoryHigh = "2500M";
      MemoryMax = "3G";
      Nice = 10;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
      DevicePolicy = "closed";
      DeviceAllow = [
        "/dev/kvm rw"
        "/dev/dri/renderD128 rw"
      ];
    };
  };

  services.nginx.virtualHosts.${tailnetHostname}.locations = {
    "= /pond".return = "308 ${tailnetOrigin}/pond/";
    "= /pond/".return =
      "302 ${tailnetOrigin}/pond/vnc.html?autoconnect=true&resize=scale&path=pond/websockify";
    "^~ /pond/".alias = "${pkgs.novnc}/share/webapps/novnc/";
    "= /pond/websockify" = mkProxyLocation pondPort ''
      if ($http_origin != "${tailnetOrigin}") {
        return 403;
      }
    '';
  };
}
