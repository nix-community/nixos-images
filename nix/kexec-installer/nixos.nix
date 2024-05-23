{ config, modulesPath, pkgs, ... }: {
  imports = [
    (modulesPath + "/installer/netboot/netboot-minimal.nix")
    ../installer.nix
    ../networkd.nix
    ../serial.nix
    ../restore-remote-access.nix
    ./module.nix
  ];
  config = {
    # Unlike NixOS, not-os uses 'systemConfig=', so we denine NixOS here
    boot.initKernelParam = ["init=${config.system.build.toplevel}"];

    systemd.services.restore-network = {
      path = [pkgs.jq];
      before = [ "network-pre.target" ];
      wants = [ "network-pre.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = [
          "${pkgs.restore-network} /root/network/addrs.json /root/network/routes-v4.json /root/network/routes-v6.json networkd=/etc/systemd/network"
        ];
      };

      unitConfig.ConditionPathExists = [
        "/root/network/addrs.json"
        "/root/network/routes-v4.json"
        "/root/network/routes-v6.json"
      ];
    };
  };
}
