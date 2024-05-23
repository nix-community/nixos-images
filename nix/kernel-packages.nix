{lib, pkgs, ...}: {
  boot.kernelPackages = lib.mkDefault (pkgs.zfs.override {
    removeLinuxDRM = pkgs.hostPlatform.isAarch64;
  }).latestCompatibleLinuxPackages;
}
