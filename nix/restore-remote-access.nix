{ lib, ... }:
let
  is2405 = lib.versionAtLeast lib.version "24.05pre";
in
{
  # We have a bug in 23.11 in combination with netboot.
  boot.initrd.systemd.enable = is2405;
  boot.initrd.systemd.services.restore-state-from-initrd = {
    unitConfig = {
      DefaultDependencies = false;
      RequiresMountsFor = "/sysroot /dev";
    };
    wantedBy = [ "initrd.target" ];
    requiredBy = [ "rw-etc.service" ];
    before = [ "rw-etc.service" ];
    serviceConfig.Type = "oneshot";
    # Restore ssh host and user keys if they are available.
    # This avoids warnings of unknown ssh keys.
    script = ''
      mkdir -m 700 -p /sysroot/root/.ssh
      mkdir -m 755 -p /sysroot/etc/ssh
      mkdir -m 755 -p /sysroot/root/network
      if [[ -f ssh/authorized_keys ]]; then
        install -m 400 ssh/authorized_keys /sysroot/root/.ssh
      fi
      install -m 400 ssh/ssh_host_* /sysroot/etc/ssh
      cp *.json /sysroot/root/network/
      if [[ -f machine-id ]]; then
        cp machine-id /sysroot/etc/machine-id
      fi
    '';
  };
  boot.initrd.postMountCommands = lib.mkIf (!is2405) ''
      mkdir -m 700 -p /mnt-root/root/.ssh
      mkdir -m 755 -p /mnt-root/etc/ssh
      mkdir -m 755 -p /mnt-root/root/network
      if [[ -f ssh/authorized_keys ]]; then
        install -m 400 ssh/authorized_keys /mnt-root/root/.ssh
      fi
      install -m 400 ssh/ssh_host_* /mnt-root/etc/ssh
      cp *.json /mnt-root/root/network/
      if [[ -f machine-id ]]; then
        cp machine-id /mnt-root/etc/machine-id
      fi
  '';
}
