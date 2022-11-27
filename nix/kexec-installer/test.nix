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

      virtualisation.memorySize = 2 * 1024 + 512;
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
    };

    node2 = { pkgs, modulesPath, ... }: {
      virtualisation.vlans = [ 1 ];
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
              "2001:DB8::1/64"
            ];
            networkConfig = {
              DHCPServer = true;
              Address = "10.0.0.1/24";
              IPv6SendRA = true;
            };
            dhcpServerConfig = {
              PoolOffset = 100;
              PoolSize = 1;
            };
          };
        };
      };
    };

  };

  testScript = { nodes, ... }: ''
    # Test whether reboot via kexec works.
    node1.wait_for_unit("multi-user.target")
    node1.succeed('kexec --load /run/current-system/kernel --initrd /run/current-system/initrd --command-line "$(</proc/cmdline)"')
    node1.execute("systemctl kexec >&2 &", check_return=False)
    node1.connected = False
    node1.connect()
    node1.wait_for_unit("multi-user.target")

    node1.wait_for_unit("sshd.service")
    host_ed25519_before = node1.succeed("cat /etc/ssh/ssh_host_ed25519_key.pub")

    node1.succeed('ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -q -N ""')
    root_ed25519_before = node1.succeed('tee /root/.ssh/authorized_keys < /root/.ssh/id_ed25519.pub')
    # Kexec node1 to the toplevel of node2 via the kexec-boot script
    node1.succeed('touch /run/foo')
    node1.fail('hello')
    node1.succeed('tar -xf ${nodes.node2.config.system.build.kexecTarball}/nixos-kexec-installer-${pkgs.system}.tar.gz -C /root')
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

    node1.shutdown()
  '';
}
