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
    node1 = { ... }: {
      virtualisation.vlans = [ ];
      virtualisation.memorySize = 4 * 1024;
      virtualisation.diskSize = 4 * 1024;
      virtualisation.useBootLoader = true;
      virtualisation.useEFIBoot = true;
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;
      services.openssh.enable = true;
    };

    node2 = { pkgs, modulesPath, ... }: {
      virtualisation.vlans = [ ];
      environment.systemPackages = [ pkgs.hello ];
      imports = [
        ./kexec-installer.nix
      ];
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

    # Check if the machine with netboot-minimal.nix profile boots up
    node2.wait_for_unit("multi-user.target")
    node2.shutdown()

    node1.wait_for_unit("sshd.service")
    host_ed25519_before = node1.succeed("cat /etc/ssh/ssh_host_ed25519_key.pub")

    node1.succeed('ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -q -N ""')
    root_ed25519_before = node1.succeed('tee /root/.ssh/authorized_keys < /root/.ssh/id_ed25519.pub')
    # Kexec node1 to the toplevel of node2 via the kexec-boot script
    node1.succeed('touch /run/foo')
    node1.fail('hello')
    node1.succeed('mkdir -p /root/kexec')
    node1.succeed('mkdir -p /root/kexec')
    node1.succeed('tar -xf ${nodes.node2.config.system.build.kexecTarball}/tarball/nixos-kexec-installer-${pkgs.system}.tar.xz -C /root/kexec')
    node1.execute('/root/kexec/kexec-boot')
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
