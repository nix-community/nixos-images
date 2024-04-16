{ pkgs, ... }:
{
  systemd.services.log-network-status = {
    wantedBy = [ "multi-user.target" ];
    # No point in restarting this. We just need this after boot
    restartIfChanged = false;

    serviceConfig = {
      Type = "oneshot";
      StandardOutput = "journal+console";
      ExecStart = [
        # Allow failures, so it still prints what interfaces we have even if we
        # not get online
        "-${pkgs.systemd}/lib/systemd/systemd-networkd-wait-online"
        "${pkgs.iproute2}/bin/ip -c addr"
        "${pkgs.iproute2}/bin/ip -c -6 route"
        "${pkgs.iproute2}/bin/ip -c -4 route"
        "${pkgs.systemd}/bin/networkctl status"
      ];
    };
  };
}
