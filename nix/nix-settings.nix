# take from srvos
{ lib, ... }:
{
  # Fallback quickly if substituters are not available.
  nix.settings.connect-timeout = 5;

  # Enable flakes
  nix.settings.extra-experimental-features = [ "nix-command" "flakes" ];
  nix.settings.extra-substituters = [ "/" ];

  # The default at 10 is rarely enough.
  nix.settings.log-lines = lib.mkDefault 25;

  # Avoid disk full issues
  nix.settings.max-free = lib.mkDefault (3000 * 1024 * 1024);
  nix.settings.min-free = lib.mkDefault (512 * 1024 * 1024);

  # TODO: cargo culted.
  nix.daemonCPUSchedPolicy = lib.mkDefault "batch";
  nix.daemonIOSchedClass = lib.mkDefault "idle";
  nix.daemonIOSchedPriority = lib.mkDefault 7;

  # Avoid copying unnecessary stuff over SSH
  nix.settings.builders-use-substitutes = true;
}
