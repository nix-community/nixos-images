{
  config,
  lib,
  modulesPath,
  pkgs,
  ...
}:
let
  writePython3 =
    pkgs.writers.makePythonWriter pkgs.python3Minimal pkgs.python3Packages
      pkgs.buildPackages.python3Packages;

  # writePython3Bin takes the same arguments as writePython3 but outputs a directory (like writeScriptBin)
  writePython3Bin = name: writePython3 "/bin/${name}";

  restore-network = writePython3Bin "restore-network" {
    flakeIgnore = [ "E501" ];
  } ./restore_routes.py;

  restore-dynamic = writePython3Bin "restore-dynamic" {
    flakeIgnore = [
      "E501"
      "E265"
    ];
  } ./restore_dynamic.py;

  # does not link with iptables enabled
  iprouteStatic = pkgs.pkgsStatic.iproute2.override { iptables = null; };
in
{
  imports = [
    (modulesPath + "/installer/netboot/netboot-minimal.nix")
    ../installer.nix
    ../networkd.nix
    ../serial.nix
    ../restore-remote-access.nix
  ];

  options = {
    system.kexec-installer.name = lib.mkOption {
      type = lib.types.str;
      default = "nixos-kexec-installer";
      description = ''
        The variant of the kexec installer to use.
      '';
    };
  };

  config = {
    boot.initrd.compressor = "xz";
    # This is a variant of the upstream kexecScript that also allows embedding
    # a ssh key.
    system.build.kexecRun = pkgs.runCommand "kexec-run" { } ''
      install -D -m 0755 ${./kexec-run.sh} $out

      sed -i \
        -e 's|@init@|${config.system.build.toplevel}/init|' \
        -e 's|@kernelParams@|${lib.escapeShellArgs config.boot.kernelParams}|' \
        $out

      ${pkgs.shellcheck}/bin/shellcheck $out
    '';

    system.build.kexecInstallerTarball = pkgs.runCommand "kexec-tarball" { } ''
      mkdir kexec $out
      cp "${config.system.build.netbootRamdisk}/initrd" kexec/initrd
      cp "${config.system.build.kernel}/${config.system.boot.loader.kernelFile}" kexec/bzImage
      cp "${config.system.build.kexecRun}" kexec/run
      cp "${pkgs.pkgsStatic.kexec-tools}/bin/kexec" kexec/kexec
      cp "${iprouteStatic}/bin/ip" kexec/ip
      ${lib.optionalString (pkgs.stdenv.hostPlatform == pkgs.stdenv.buildPlatform) ''
        kexec/ip -V
        kexec/kexec --version
      ''}
      tar -czvf $out/${config.system.kexec-installer.name}-${pkgs.stdenv.hostPlatform.system}.tar.gz kexec
    '';

    systemd.services = {
      restore-dynamic = {
        path = [ pkgs.iproute2 ];
        after = [ "network-pre.target" ];
        wants = [ "network-pre.target" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = [
            (builtins.concatStringsSep " " [
              "${restore-dynamic}/bin/restore-dynamic"
              "/root/network/iproute2/addrs.json"
              "/root/network/iproute2/routes"
            ])
          ];
        };
        unitConfig.ConditionPathExists = [ "/root/network/iproute2/addrs.json" ];
      };

      restore-network = {
        before = [ "network-pre.target" ];
        wants = [ "network-pre.target" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = [
            (builtins.concatStringsSep " " [
              "${restore-network}/bin/restore-network"

              "/root/network/iproute2/addrs.json"
              "/root/network/iproute2/routes-v4.json"
              "/root/network/iproute2/routes-v6.json"

              "/root/network/networkd/list.json"
              "/root/network/networkd/iface"

              "/etc/systemd/network"
            ])
          ];
        };

        unitConfig.ConditionPathExists = [
          "/root/network/iproute2/addrs.json"
          "/root/network/iproute2/routes-v4.json"
          "/root/network/iproute2/routes-v6.json"
        ];
      };
    };
  };
}
