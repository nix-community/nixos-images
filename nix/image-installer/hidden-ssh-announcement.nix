{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.hidden-ssh-announce = {
    enable = lib.mkEnableOption "hidden-ssh-announce";
    script = lib.mkOption {
      type = lib.types.package;
      default = pkgs.writers.writeDash "test-output" "echo $1";
      description = ''
        script to run when the hidden tor service was started and they hostname is known.
        takes the hostname as $1
      '';
    };
  };

  config = lib.mkIf config.hidden-ssh-announce.enable {
    services.openssh.enable = true;
    services.tor = {
      enable = true;
      relay.onionServices.hidden-ssh = {
        version = 3;
        map = [
          {
            port = 22;
            target.port = 22;
          }
        ];
      };
      client.enable = true;
    };
    systemd.services.hidden-ssh-announce = {
      description = "announce hidden ssh";
      after = [
        "tor.service"
        "network-online.target"
      ];
      wants = [
        "tor.service"
        "network-online.target"
      ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        # ${pkgs.tor}/bin/torify
        ExecStart = pkgs.writeShellScript "announce-hidden-service" ''
          set -efu
          until test -e ${config.services.tor.settings.DataDirectory}/onion/hidden-ssh/hostname; do
            echo "still waiting for ${config.services.tor.settings.DataDirectory}/onion/hidden-ssh/hostname"
            sleep 1
          done

          ${config.hidden-ssh-announce.script} "$(cat ${config.services.tor.settings.DataDirectory}/onion/hidden-ssh/hostname)"
        '';
        PrivateTmp = "true";
        User = "tor";
        Type = "oneshot";
      };
    };
  };
}
