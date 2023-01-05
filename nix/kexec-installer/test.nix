{ pkgs ? import <nixpkgs> {} }:

let
  makeTest = import (pkgs.path + "/nixos/tests/make-test-python.nix");
  makeTest' = args: makeTest args {
    inherit pkgs;
    inherit (pkgs) system;
  };

in makeTest' {
  name = "kexec-installer";
  meta = with pkgs.lib.maintainers; {
    maintainers = [ mic92 ];
  };

  nodes = {
    node1 = { modulesPath, ... }: {
      virtualisation.vlans = [ 1 ];
      environment.noXlibs = false; # avoid recompilation
      imports = [
        (modulesPath + "/profiles/minimal.nix")
      ];

      virtualisation.memorySize = 2 * 1024 + 767;
      virtualisation.diskSize = 4 * 1024;
      virtualisation.useBootLoader = true;
      virtualisation.useEFIBoot = true;
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;
      services.openssh.enable = true;

      networking = {
        useNetworkd = true;
        useDHCP = false;
      };

      systemd.network = {
        networks = {
          # systemd-networkd will load the first network unit file
          # that matches, ordered lexiographically by filename.
          # /etc/systemd/network/{40-eth1,99-main}.network already
          # exists. This network unit must be loaded for the test,
          # however, hence why this network is named such.
          "01-eth1" = {
            name = "eth1";
            address = [
              # Some static addresses that we want to see in the kexeced image
              "192.168.42.1/24"
              "42::1/64"
            ];
            routes = [
              # Some static routes that we want to see in the kexeced image
              { routeConfig = { Destination = "192.168.43.0/24"; }; }
              { routeConfig = { Destination = "192.168.44.0/24"; Gateway = "192.168.43.1"; }; }
              { routeConfig = { Destination = "43::0/64"; }; }
              { routeConfig = { Destination = "44::1/64"; Gateway = "43::1"; }; }
            ];
            networkConfig = {
              DHCP = "yes";
              IPv6AcceptRA = true;
            };
          };
        };
      };
    };

    node2 = { pkgs, modulesPath, ... }: {
      environment.systemPackages = [ pkgs.hello ];
      imports = [
        ./module.nix
      ];
    };

    router = { config, pkgs, ... }: {
      virtualisation.vlans = [ 1 ];
      networking = {
        useNetworkd = true;
        useDHCP = false;
        firewall.enable = false;
      };
      systemd.network = {
        networks = {
          # systemd-networkd will load the first network unit file
          # that matches, ordered lexiographically by filename.
          # /etc/systemd/network/{40-eth1,99-main}.network already
          # exists. This network unit must be loaded for the test,
          # however, hence why this network is named such.
          "01-eth1" = {
            name = "eth1";
            address = [
              "2001:db8::1/64"
            ];
            ipv6Prefixes = [
              { ipv6PrefixConfig = { Prefix = "2001:db8::/64"; AddressAutoconfiguration = true; OnLink = true; }; }
            ];
            # does not work in 22.11
            #ipv6RoutePrefixes = [ { ipv6RoutePrefixConfig = { Route = "::/0"; LifetimeSec = 3600; }; }];
            extraConfig = ''
              [IPv6RoutePrefix]
              Route = ::/0
              LifetimeSec = 3600
            '';
            networkConfig = {
              DHCPServer = true;
              Address = "10.0.0.1/24";
              IPv6SendRA = true;
            };
            dhcpServerConfig = {
              PoolOffset = 100;
              PoolSize = 1;
              EmitRouter = true;
            };
          };
        };
      };
    };

  };

  testScript = { nodes, ... }: ''
    # Test whether reboot via kexec works.

    router.wait_for_unit("network-online.target")
    router.succeed("ip addr >&2")
    router.succeed("ip route >&2")
    router.succeed("ip -6 route >&2")
    router.succeed("networkctl status eth1 >&2")

    node1.wait_until_succeeds("ping -c1 10.0.0.1")
    node1.wait_until_succeeds("ping -c1 2001:db8::1")
    node1.succeed("ip addr >&2")
    node1.succeed("ip route >&2")
    node1.succeed("ip -6 route >&2")
    node1.succeed("networkctl status eth1 >&2")

    host_ed25519_before = node1.succeed("cat /etc/ssh/ssh_host_ed25519_key.pub")
    node1.succeed('ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -q -N ""')
    root_ed25519_before = node1.succeed('tee /root/.ssh/authorized_keys < /root/.ssh/id_ed25519.pub')

    # Kexec node1 to the toplevel of node2 via the kexec-boot script
    node1.succeed('touch /run/foo')
    node1.fail('hello')
    node1.succeed('tar -xf ${nodes.node2.system.build.kexecTarball}/nixos-kexec-installer-${pkgs.system}.tar.gz -C /root')
    node1.execute('/root/kexec/run')
    # wait for machine to kexec
    node1.execute('sleep 9999', check_return=False)
    node1.succeed('! test -e /run/foo')
    node1.succeed('hello')
    node1.succeed('[ "$(hostname)" = "node2" ]')
    node1.wait_for_unit("sshd.service")

    host_ed25519_after = node1.succeed("cat /etc/ssh/ssh_host_ed25519_key.pub")
    assert host_ed25519_before == host_ed25519_after, f"{host_ed25519_before} != {host_ed25519_after}"

    root_ed25519_after = node1.succeed("cat /root/.ssh/authorized_keys")
    assert root_ed25519_before == root_ed25519_after, f"{root_ed25519_before} != {root_ed25519_after}"

    # See if we can reach the router after kexec
    node1.wait_for_unit("restore-network.service")
    node1.wait_until_succeeds("cat /etc/systemd/network/eth1.network >&2")
    node1.wait_until_succeeds("ping -c1 10.0.0.1")
    node1.wait_until_succeeds("ping -c1 2001:db8::1")

    # Check if static addresses have been restored
    node1.wait_until_succeeds("ping -c1 42::1")
    node1.wait_until_succeeds("ping -c1 192.168.42.1")

    out = node1.wait_until_succeeds("ip route get 192.168.43.2")
    print(out)
    assert "192.168.43.2 dev eth1" in out

    out = node1.wait_until_succeeds("ip route get 192.168.44.2")
    print(out)
    assert "192.168.44.2 via 192.168.43.1" in out

    out = node1.wait_until_succeeds("ip route get 43::2")
    print(out)
    assert "43::2 from :: dev eth1" in out

    out = node1.wait_until_succeeds("ip route get 44::2")
    print(out)
    assert "44::2 from :: via 43::1" in out

    node1.succeed("ip addr >&2")
    node1.succeed("ip route >&2")
    node1.succeed("ip -6 route >&2")
    node1.succeed("networkctl status eth1 >&2")

    node1.shutdown()
  '';
}
