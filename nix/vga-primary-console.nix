{ pkgs, lib, ... }:
{
  # VGA-primary console configuration for local installations
  # Multiple consoles: all receive kernel messages, but the LAST one becomes /dev/console (primary for systemd)
  # VGA is last (primary) for local installations where a monitor is present
  boot.kernelParams =
    (lib.optional (
      pkgs.stdenv.hostPlatform.isAarch32 || pkgs.stdenv.hostPlatform.isAarch64
    ) "console=ttyAMA0,115200")
    ++ (lib.optional (pkgs.stdenv.hostPlatform.isRiscV) "console=ttySIF0,115200")
    ++ [ "console=ttyS0,115200" ]
    ++ [ "console=tty0" ];
}
