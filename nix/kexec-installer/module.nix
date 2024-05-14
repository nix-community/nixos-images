{ config, lib, pkgs, ... }: {
  options = {
    system.kexec-installer.name = lib.mkOption {
      type = lib.types.str;
      default = "nixos-kexec-installer";
      description = ''
        The variant of the kexec installer to use.
      '';
    };
    boot.initKernelParam = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = ''
        The kernel parameter carrying the a string reference to the activation package.
      '';
    };
  };

  config = {
    nixpkgs.overlays = [
      (final: prev: {
        restore-network = prev.writers.writeBash "restore-network" ./restore_routes.sh;
        # does not link with iptables enabled
        iprouteStatic = prev.pkgsStatic.iproute2.override { iptables = null; };
      })
    ];
    # This is a variant of the upstream kexecScript that also allows embedding
    # a ssh key.
    system.build.kexecRun = pkgs.runCommand "kexec-run" { } ''
      install -D -m 0755 ${./kexec-run.sh} $out

      sed -i \
        -e 's|@kernelParams@|${lib.escapeShellArgs (config.boot.kernelParams ++ config.boot.initKernelParam)}|' \
        $out

      ${pkgs.shellcheck}/bin/shellcheck $out
    '';

    system.build.kexecTarball = pkgs.runCommand "kexec-tarball" { } ''
      mkdir kexec $out
      cp "${config.system.build.netbootRamdisk}/initrd" kexec/initrd
      cp "${config.system.build.kernel}/${config.system.boot.loader.kernelFile}" kexec/bzImage
      cp "${config.system.build.kexecRun}" kexec/run
      cp "${pkgs.pkgsStatic.kexec-tools}/bin/kexec" kexec/kexec
      cp "${pkgs.iprouteStatic}/bin/ip" kexec/ip
      ${lib.optionalString (pkgs.hostPlatform == pkgs.buildPlatform) ''
        kexec/ip -V
        kexec/kexec --version
      ''}
      tar -czvf $out/${config.system.kexec-installer.name}-${pkgs.stdenv.hostPlatform.system}.tar.gz kexec
    '';


    # for detection if we are on kexec
    environment.etc.is_kexec.text = "true";
  };
}
