{ pkgs
, lib
, kexecTarball
}:

let
  makeTest = import (pkgs.path + "/nixos/tests/make-test-python.nix");
  makeTest' = args: makeTest args {
    inherit pkgs;
    inherit (pkgs) system;
  };
in
makeTest' {
  name = "kexec-installer";
  meta = with pkgs.lib.maintainers; {
    maintainers = [ mic92 ];
  };

  nodes = {
    node1 = { modulesPath, ... }: {
      virtualisation.vlans = [ ];
      environment.noXlibs = false; # avoid recompilation
      imports = [
        (modulesPath + "/profiles/minimal.nix")
      ];

      system.extraDependencies = [ kexecTarball ];
      virtualisation.memorySize = 1 * 1024;
      virtualisation.diskSize = 4 * 1024;
      virtualisation.forwardPorts = [{
        host.port = 2222;
        guest.port = 22;
      }];

      services.openssh.enable = true;

      networking.useNetworkd = true;
      networking.useDHCP = false;

      users.users.root.openssh.authorizedKeys.keyFiles = [ ./ssh-keys/id_ed25519.pub ];

      systemd.network = {
        networks = {
          # systemd-networkd will load the first network unit file
          # that matches, ordered lexiographically by filename.
          # /etc/systemd/network/{40-eth1,99-main}.network already
          # exists. This network unit must be loaded for the test,
          # however, hence why this network is named such.

          "01-eth0" = {
            name = "eth0";
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
            networkConfig = { DHCP = "yes"; IPv6AcceptRA = true; };
          };
        };
      };
    };
  };

  testScript = ''
    import time
    import subprocess
    import socket
    import http.server
    from threading import Thread
    from typing import Optional

    start_all()

    class DualStackServer(http.server.HTTPServer):
        def server_bind(self):
            self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
            return super().server_bind()
    DualStackServer.address_family = socket.AF_INET6
    httpd = DualStackServer(("::", 0), http.server.SimpleHTTPRequestHandler)

    http.server.HTTPServer.address_family = socket.AF_INET6
    port = httpd.server_port
    def serve_forever(httpd):
        with httpd:
            httpd.serve_forever()
    thread = Thread(target=serve_forever, args=(httpd, ))
    thread.setDaemon(True)
    thread.start()

    node1.wait_until_succeeds(f"curl -v -I http://10.0.2.2:{port}")
    node1.wait_until_succeeds(f"curl -v -I http://[fec0::2]:{port}")

    node1.succeed("ip addr >&2")
    node1.succeed("ip route >&2")
    node1.succeed("ip -6 route >&2")
    node1.succeed("networkctl status eth0 >&2")

    def ssh(cmd: list[str], check: bool = True, stdout: Optional[int] = None) -> subprocess.CompletedProcess[str]:
        ssh_cmd = [
          "${pkgs.openssh}/bin/ssh",
          "-o", "StrictHostKeyChecking=no",
          "-o", "ConnectTimeout=1",
          "-i", "${./ssh-keys/id_ed25519}",
          "-p", "2222",
          "root@127.0.0.1",
          "--"
        ] + cmd
        print(" ".join(ssh_cmd))
        return subprocess.run(ssh_cmd,
                              text=True,
                              check=check,
                              stdout=stdout)


    while not ssh(["true"], check=False).returncode == 0:
        time.sleep(1)
    ssh(["cp", "--version"])

    host_ed25519_before = node1.succeed("cat /etc/ssh/ssh_host_ed25519_key.pub").strip()
    node1.succeed('ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -q -N ""')
    root_ed25519_before = node1.succeed('tee /root/.ssh/authorized_keys < /root/.ssh/id_ed25519.pub').strip()

    # Kexec node1 to the toplevel of node2 via the kexec-boot script
    node1.succeed('touch /run/foo')
    old_machine_id = node1.succeed("cat /etc/machine-id").strip()
    node1.fail('parted --version >&2')
    node1.succeed('tar -xf ${kexecTarball}/nixos-kexec-installer-noninteractive-${pkgs.system}.tar.gz -C /root')
    node1.succeed('/root/kexec/ip -V >&2')
    node1.succeed('/root/kexec/kexec --version >&2')
    node1.succeed('/root/kexec/run >&2')

    # the kexec script will sleep 6s before doing anything, so do we here.
    time.sleep(6)

    # wait for kexec to finish
    while ssh(["true"], check=False).returncode == 0:
        print("Waiting for kexec to finish...")
        time.sleep(1)

    while ssh(["true"], check=False).returncode != 0:
        print("Waiting for node2 to come up...")
        time.sleep(1)

    while ssh(["systemctl is-active restore-network"], check=False).returncode != 0:
        print("Waiting for network to be restored...")
        time.sleep(1)
    ssh(["systemctl", "status", "restore-network"])

    print(ssh(["ip", "addr"]))
    print(ssh(["ip", "route"]))
    print(ssh(["ip", "-6", "route"]))
    print(ssh(["networkctl", "status"]))

    new_machine_id = ssh(["cat", "/etc/machine-id"], stdout=subprocess.PIPE).stdout.strip()
    assert old_machine_id == new_machine_id, f"{old_machine_id} != {new_machine_id}, machine-id changed"

    assert ssh(["ls", "-la", "/run/foo"], check=False).returncode != 0, "kexeced node1 still has /run/foo"
    print(ssh(["parted", "--version"]))
    host = ssh(["hostname"], stdout=subprocess.PIPE).stdout.strip()
    assert host == "nixos-installer", f"hostname is {host}, not nixos-installer"

    host_ed25519_after = ssh(["cat", "/etc/ssh/ssh_host_ed25519_key.pub"], stdout=subprocess.PIPE).stdout.strip()
    assert host_ed25519_before == host_ed25519_after, f"'{host_ed25519_before}' != '{host_ed25519_after}'"

    root_ed25519_after = ssh(["cat", "/root/.ssh/authorized_keys"], stdout=subprocess.PIPE).stdout.strip()
    assert root_ed25519_before in root_ed25519_after, f"'{root_ed25519_before}' not included in '{root_ed25519_after}'"

    print(ssh(["cat", "/etc/systemd/network/00-eth0.network"]))
    ssh(["curl", "-v", "-I", f"http://10.0.2.2:{port}"])
    ssh(["curl", "-v", "-I", f"http://[fec0::2]:{port}"])

    ## Check if static addresses have been restored
    ssh(["ping", "-c1", "42::1"])
    ssh(["ping", "-c1", "192.168.42.1"])

    out = ssh(["ip", "route", "get", "192.168.43.2"], stdout=subprocess.PIPE).stdout
    print(out)
    assert "192.168.43.2 dev" in out, f"route to `192.168.43.2 dev` not found: {out}"

    out = ssh(["ip", "route", "get", "192.168.44.2"], stdout=subprocess.PIPE).stdout
    print(out)
    assert "192.168.44.2 via 192.168.43.1" in out, f"route to `192.168.44.2 via 192.168.43.1` not found: {out}"

    out = ssh(["ip", "route", "get", "43::2"], stdout=subprocess.PIPE).stdout
    print(out)
    assert "43::2 from :: dev" in out, f"route `43::2 from dev` not found: {out}"

    out = ssh(["ip", "route", "get", "44::2"], stdout=subprocess.PIPE).stdout
    print(out)
    assert "44::2 from :: via 43::1" in out, f"route to `44::2 from :: via 43::1` not found: {out}"

    node1.crash()
  '';
}
