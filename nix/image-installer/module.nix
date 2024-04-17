{
  lib,
  pkgs,
  modulesPath,
  ...
}:
let
  network-status = pkgs.writeShellScript "network-status" ''
    export PATH=${
      lib.makeBinPath (
        with pkgs;
        [
          iproute2
          coreutils
          gnugrep
          nettools
          gum
        ]
      )
    }
    set -efu -o pipefail
    msgs=()
    if [[ -e /var/shared/qrcode.utf8 ]]; then
      qrcode=$(gum style --border-foreground 240 --border normal "$(< /var/shared/qrcode.utf8)")
      msgs+=("$qrcode")
    fi
    network_status="Root password: $(cat /var/shared/root-password)
    Local network addresses:
    $(ip -brief -color addr | grep -v 127.0.0.1)
    $([[ -e /var/shared/onion-hostname ]] && echo "Onion address: $(cat /var/shared/onion-hostname)" || echo "Onion address: Waiting for tor network to be ready...")
    Multicast DNS: $(hostname).local"
    network_status=$(gum style --border-foreground 240 --border normal "$network_status")
    msgs+=("$network_status")
    msgs+=("Press 'Ctrl-C' for console access")

    gum join --vertical "''${msgs[@]}"
  '';
in
{
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-base.nix")
    ../installer.nix
    ./wifi.nix
    ./hidden-ssh-announcement.nix
  ];
  systemd.tmpfiles.rules = [ "d /var/shared 0777 root root - -" ];
  services.openssh.settings.PermitRootLogin = "yes";
  system.activationScripts.root-password = ''
    mkdir -p /var/shared
    ${pkgs.xkcdpass}/bin/xkcdpass --numwords 3 --delimiter - --count 1 > /var/shared/root-password
    echo "root:$(cat /var/shared/root-password)" | chpasswd
  '';
  hidden-ssh-announce = {
    enable = true;
    script = pkgs.writeShellScript "write-hostname" ''
      set -efu
      export PATH=${
        lib.makeBinPath (
          with pkgs;
          [
            iproute2
            coreutils
            jq
            qrencode
          ]
        )
      }

      mkdir -p /var/shared
      echo "$1" > /var/shared/onion-hostname
      local_addrs=$(ip -json addr | jq '[map(.addr_info) | flatten | .[] | select(.scope == "global") | .local]')
      jq -nc \
        --arg password "$(cat /var/shared/root-password)" \
        --arg onion_address "$(cat /var/shared/onion-hostname)" \
        --argjson local_addrs "$local_addrs" \
        '{ pass: $password, tor: $onion_address, addrs: $local_addrs }' \
        > /var/shared/login.json
      cat /var/shared/login.json | qrencode -s 2 -m 2 -t utf8 -o /var/shared/qrcode.utf8
    '';
  };

  services.getty.autologinUser = lib.mkForce "root";

  console.earlySetup = true;
  console.font = lib.mkDefault "${pkgs.terminus_font}/share/consolefonts/ter-u22n.psf.gz";

  # Less ipv6 addresses to reduce the noise
  networking.tempAddresses = "disabled";

  # Tango theme: https://yayachiken.net/en/posts/tango-colors-in-terminal/
  console.colors = lib.mkDefault [
    "000000"
    "CC0000"
    "4E9A06"
    "C4A000"
    "3465A4"
    "75507B"
    "06989A"
    "D3D7CF"
    "555753"
    "EF2929"
    "8AE234"
    "FCE94F"
    "739FCF"
    "AD7FA8"
    "34E2E2"
    "EEEEEC"
  ];

  programs.bash.interactiveShellInit = ''
    if [[ "$(tty)" =~ /dev/(tty1|hvc0|ttyS0)$ ]]; then
      # workaround for https://github.com/NixOS/nixpkgs/issues/219239
      systemctl restart systemd-vconsole-setup.service

      watch --no-title --color ${network-status}
    fi
  '';

  # No one got time for xz compression.
  isoImage.squashfsCompression = "zstd";
  isoImage.isoName = lib.mkForce "nixos-installer-${pkgs.system}.iso";
}
