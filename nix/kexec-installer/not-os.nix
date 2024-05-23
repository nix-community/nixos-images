{ pkgs, config, lib, ... }: {
  imports = [
    ../serial.nix
    ../system-packages.nix
    # ../kernel-packages.nix
    ./module.nix
  ];
  config = {
    environment.systemPackages = [
      pkgs.lldpd
      pkgs.radvd
      pkgs.avahi
      # nixos-anywhere
      pkgs.rsync
      pkgs.parted
      pkgs.gptfdisk
      # for tests
      pkgs.curl
    ];
    # already set in not os, copied for reference
    # boot.kernelParams = ["systemConfig=${config.system.build.toplevel}"];
    boot.initKernelParam = [ "root=/root.squashfs" ];

    system.build.netbootRamdisk = pkgs.makeInitrdNG {
      compressor =
        if lib.versionAtLeast config.boot.kernelPackages.kernel.version "5.9"
        then "zstd"
        else "gzip";
      prepend = [ "${config.system.build.initialRamdisk}/initrd" ];

      contents =
        [ { object = config.system.build.squashfs;
            symlink = "/root.squashfs";
          }
        ];
    };

    not-os.nix = true;
    not-os.dhcp = true;

    # Restore ssh host and user keys if they are available.
    # This avoids warnings of unknown ssh keys.
    # Also place the network config
    not-os.postMount = ''
      mkdir -m 755 -p /mnt/etc/ssh
      mkdir -m 700 -p /mnt/etc/ssh/authorized_keys.d
      if [[ -f ssh/authorized_keys ]]; then
        install -m 400 ssh/authorized_keys /mnt/etc/ssh/authorized_keys.d/root
      fi
      install -m 400 ssh/ssh_host_* /mnt/etc/ssh

      mkdir -m 755 -p /mnt/root/network
      cp *.json /mnt/root/network/
    '';

    not-os.simpleStaticIp = true;  # according to qemue default networking

    not-os.extraStartup = ''
      if [ -f /root/network/addrs.json -a -f /root/network/routes-v4.json -a -f /root/network/routes-v6.json ]; then
        ${pkgs.restore-network} /root/network/addrs.json /root/network/routes-v4.json /root/network/routes-v6.json use-ip
      fi
      ip link set dev lo up
      ip addr
      ip route
    '';

    boot.initrd.kernelModules = [ "virtio" "virtio_pci" "virtio_net" "virtio_rng" "virtio_blk" "virtio_console" ];

    environment.etc = {
      # # Link Layer Discovery Protocol
      # "service/lldpd/run".source = pkgs.writeScript "lldpd_run" ''
      #   #!${pkgs.runtimeShell}
      #   echo Start lldp daemon
      #   ${pkgs.lldpd}/bin/lldpd 
      # '';
      # # IPv6 Router Advertisement
      # "service/radvd/run".source = pkgs.writeScript "lldpd_run" ''
      #   #!${pkgs.runtimeShell}
      #   echo Start radv daemon
      #   ${pkgs.radvd}/bin/radvd
      # '';
      # # Multicast DNS (mDNS)
      # "service/avahi/run".source = pkgs.writeScript "lldpd_run" ''
      #   #!${pkgs.runtimeShell}
      #   echo Start avahi daemon
      #   ${pkgs.avahi}/bin/avahi-daemon -D -f ${pkgs.avahi}/etc/avahi/avahi-daemon.conf
      # '';
    };
  };
}
