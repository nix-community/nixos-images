{ lib, ... }:
{
  # Not really needed. Saves a few bytes and the only service we are running is sshd, which we want to be reachable.
  networking.firewall.enable = false;

  networking.useNetworkd = true;
  systemd.network.enable = true;

  # mdns
  networking.firewall.allowedUDPPorts = [ 5353 ];
  systemd.network.networks."99-ethernet-default-dhcp".networkConfig.MulticastDNS = lib.mkDefault "yes";
  systemd.network.networks."99-wireless-client-dhcp".networkConfig.MulticastDNS = lib.mkDefault "yes";
}
