{
  lib,
  pkgs,
  modulesPath,
  ...
}:
let
  network-status = pkgs.callPackage ../network-status {};
in
{
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-base.nix")
    ../installer.nix
    ../noveau-workaround.nix
    ./tor-ssh.nix
    ./wifi.nix
  ];
  systemd.tmpfiles.rules = [ "d /var/shared 0777 root root - -" ];
  services.openssh.settings.PermitRootLogin = "yes";
  system.activationScripts.root-password = ''
    mkdir -p /var/shared
    ${pkgs.xkcdpass}/bin/xkcdpass --numwords 3 --delimiter - --count 1 > /var/shared/root-password
    echo "root:$(cat /var/shared/root-password)" | chpasswd
  '';
  # Enable Tor hidden SSH service - network-status will read hostname directly
  tor-ssh.enable = true;

  services.getty.autologinUser = lib.mkForce "root";

  console.earlySetup = true;
  console.font = lib.mkDefault "${pkgs.terminus_font}/share/consolefonts/ter-u22n.psf.gz";

  environment.systemPackages = [ network-status ];

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

      ${network-status}/bin/network-status
    fi
  '';

  # No one got time for xz compression.
  isoImage.squashfsCompression = "zstd";
} // (if lib.versionAtLeast lib.version "25.03pre" then {
  image.baseName = lib.mkForce "nixos-installer-${pkgs.system}";
} else {
  isoImage.isoName = lib.mkForce "nixos-installer-${pkgs.system}.iso";
})
