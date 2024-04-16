{ pkgs, lib, ... }:
{
  # IPMI SOL console redirection stuff
  boot.kernelParams =
    [ "console=tty0" ]
    ++ (lib.optional (
      pkgs.stdenv.hostPlatform.isAarch32 || pkgs.stdenv.hostPlatform.isAarch64
    ) "console=ttyAMA0,115200")
    ++ (lib.optional (pkgs.stdenv.hostPlatform.isRiscV) "console=ttySIF0,115200")
    ++ [ "console=ttyS0,115200" ];
}
