{ config, lib, modulesPath, pkgs, ... }:
{
  imports = [
    (modulesPath + "/installer/netboot/netboot-minimal.nix")
  ];

  # We are stateless, so just default to latest.
  system.stateVersion = config.system.nixos.version;

  # This is a variant of the upstream kexecScript that also allows embedding
  # a ssh key.
  system.build.kexecBoot = lib.mkForce (pkgs.writeScript "kexec-boot" ''
    #!/usr/bin/env bash
    set -ex
    shopt -s nullglob
    SCRIPT_DIR=$( cd -- "$( dirname -- "''${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
    INITRD_TMP=$(mktemp -d)
    cd "$INITRD_TMP"
    pwd
    mkdir initrd initrd/ssh
    pushd initrd
    if [ -e /root/.ssh/authorized_keys ]; then
      cat /root/.ssh/authorized_keys >> ssh/authorized_keys
    fi
    if [ -e /etc/ssh/authorized_keys.d/root ]; then
      cat /etc/ssh/authorized_keys.d/root >> ssh/authorized_keys
    fi
    for p in /etc/ssh/ssh_host_*; do
      cp -a "$p" ssh
    done
    find -type f | cpio -o -H newc | gzip -9 > ../extra.gz
    popd
    cat "''${SCRIPT_DIR}/initrd.gz" extra.gz > final.gz

    "$SCRIPT_DIR/kexec" --load "''${SCRIPT_DIR}/bzImage" \
      --initrd=final.gz \
      --command-line "init=${config.system.build.toplevel}/init ${toString config.boot.kernelParams}"

    # kexec will map the new kernel in memory so we can remove the kernel at this point
    rm -r "$INITRD_TMP"

    # Disconnect our background kexec from the terminal
    if [[ -e /dev/kmsg ]]; then
      # this makes logging visible in `dmesg`, or the system consol or tools like journald
      exec > /dev/kmsg 2>&1
    else
      exec > /dev/null 2>&1
    fi
    # We will kexec in background so we can cleanly finish the script before the hosts go down.
    # This makes integration with tools like terraform easier.
    nohup bash -c "sleep 6 && '$SCRIPT_DIR/kexec' -e" &
  '');

  system.build.kexecTarball = pkgs.callPackage (pkgs.path + "/nixos/lib/make-system-tarball.nix") {
    fileName = "nixos-kexec-installer-${pkgs.stdenv.hostPlatform.system}";
    contents = [
      {
        target = "/initrd.gz";
        source = "${config.system.build.netbootRamdisk}/initrd";
      }
      {
        target = "/bzImage";
        source = "${config.system.build.kernel}/${config.system.boot.loader.kernelFile}";
      }
      {
        target = "/kexec-boot";
        source = config.system.build.kexecBoot;
      }
      {
        target = "/kexec";
        source = "${pkgs.pkgsStatic.kexec-tools}/bin/kexec";
      }
    ];
  };

  documentation.enable = false;
  # Not really needed. Saves a few bytes and the only service we are running is sshd, which we want to be reachable.
  networking.firewall.enable = false;

  # Restore ssh host and user keys if they are available.
  # This avoids warnings of unknown ssh keys.
  boot.initrd.postMountCommands = ''
    mkdir -p /mnt-root/etc/ssh /mnt-root/root/.ssh
    if [[ -f /ssh/authorized_keys ]]; then
      cp ssh/authorized_keys /mnt-root/root/.ssh/
    fi
    cp ssh/ssh_host_* /mnt-root/etc/ssh
  '';
}
