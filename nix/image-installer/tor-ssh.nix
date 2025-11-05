{
  config,
  lib,
  ...
}:
{
  options.tor-ssh = {
    enable = lib.mkEnableOption "tor-ssh";
  };

  config = lib.mkIf config.tor-ssh.enable {
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
  };
}
