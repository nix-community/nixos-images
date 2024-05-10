# This module attempts to be a workaround to
# remove the dependency of pearl from the
# crictical path of using kexec images
# in combination with nixos-anywhere

# THIS IS NOT FUNCTIONAL
# POTENTIAL SAVING: ~80MB

# TODO:
# - It's a proof of concept to calculate the saving (with nix-tree)
# - I used some AI to get the initial transcript in bash and c
# - If you, unlike me, know enough C please consider helping to finish the rewrite

{ config, lib, pkgs, utils, ... }: {
  nixpkgs.overlays = [
    (final: prev: {
      # avoid perl ~50MB - dummy
      syslinux = prev.coreutils;
    })
  ];
  # avoid packages that depend on perl
  system.disableInstallerTools = true;
  system.switch.enable = false;
  # reimplement in c to avoid dependency on perl
  system.build.etcActivationCommands = let
    setup-etc = pkgs.writeCBin "setup-etc" (builtins.readFile ./setup-etc.c);
    etc = config.system.build.etc;
  in lib.mkForce 
    ''
      # Set up the statically computed bits of /etc.
      echo "setting up /etc..."
      ${setup-etc}/bin/setup-etc ${etc}/etc
    '';
  system.activationScripts.users.text = let
    cfg = config.users;
    spec = pkgs.writeText "users-groups.json" (builtins.toJSON {
      inherit (cfg) mutableUsers;
      users = lib.mapAttrsToList (_: u:
        { inherit (u)
            name uid group description home homeMode createHome isSystemUser
            password hashedPasswordFile hashedPassword
            autoSubUidGidRange subUidRanges subGidRanges
            initialPassword initialHashedPassword expires;
          shell = utils.toShellPath u.shell;
        }) cfg.users;
      groups = builtins.attrValues cfg.groups;
    });
    # update-users-groups = pkgs.writers.writeBashBin "update-users-groups" (builtins.readFile ./update-users-groups.sh);
    update-users-groups = pkgs.writeCBin "update-users-groups" (builtins.readFile ./update-users-groups.c);
  in lib.mkForce ''
      install -m 0700 -d /root
      install -m 0755 -d /home

      ${update-users-groups}/bin/update-users-groups ${spec}
  '';
}
