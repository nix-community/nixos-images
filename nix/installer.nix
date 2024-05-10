{ config, lib, pkgs, ... }: {
  # more descriptive hostname than just "nixos"
  networking.hostName = lib.mkDefault "nixos-installer";

  # We are stateless, so just default to latest.
  system.stateVersion = config.system.nixos.version;

  # use latest kernel we can support to get more hardware support
  boot.kernelPackages = lib.mkDefault (pkgs.zfs.override {
    removeLinuxDRM = pkgs.hostPlatform.isAarch64;
  }).latestCompatibleLinuxPackages;
  boot.zfs.removeLinuxDRM = lib.mkDefault pkgs.hostPlatform.isAarch64;

  documentation.enable = lib.mkForce false;

  # reduce closure size through package set crafting
  # where there's no otherwise globally effective
  # config setting available
  # TODO: some are candidates for a long-term upstream solution
  nixpkgs.overlays = [
    (final: prev: {
      # save ~12MB by not bundling manpages
      coreutils-full = prev.coreutils;
      # save ~20MB by making them minimal
      util-linux = prev.util-linux.override {
        nlsSupport = false;
        ncursesSupport = false;
        systemdSupport = false;
        translateManpages = false;
      };
      # save ~6MB by removing one bash 
      bashInteractive = prev.bash;
      # saves ~25MB
      systemd = prev.systemd.override {
        pname = "systemd-slim";
        withDocumentation = false;
        withCoredump = false;
        withFido2 = false;
        withRepart = false;
        withMachined = false;
        withRemote = false;
        withTpm2Tss = false;
        withLibBPF = false;
        withAudit = false;
        withCompression = false;
        withImportd = false;
        withPortabled = false;
      };
    })
  ];
  systemd.coredump.enable = false;


  environment.systemPackages = [
    # for zapping of disko
    pkgs.jq
    # for copying extra files of nixos-anywhere
    pkgs.rsync
    # for installing nixos via nixos-anywhere
    config.system.build.nixos-enter
    config.system.build.nixos-install
  ];

  imports = [
    ./nix-settings.nix
  ];

  # Don't add nixpkgs to the image to save space, for our intended use case we don't need it
  system.installer.channel.enable = false;
}
