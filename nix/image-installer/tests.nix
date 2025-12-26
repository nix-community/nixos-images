{
  pkgs,
  lib,
  nixpkgs,
  nixos,
  nixosModules,
}:

let
  testConfig = (
    nixos [
      (
        { modulesPath, ... }:
        {
          imports = [
            nixosModules.image-installer
            "${modulesPath}/testing/test-instrumentation.nix"
          ];
        }
      )
    ]
  );
  iso = testConfig.config.system.build.isoImage;
  mkStartCommand =
    {
      memory ? 2048,
      cdrom ? null,
      usb ? null,
      uefi ? false,
      extraFlags ? [ ],
    }:
    let
      qemu-common = import (nixpkgs + "/nixos/lib/qemu-common.nix") { inherit lib pkgs; };
      qemu = qemu-common.qemuBinary pkgs.qemu_test;

      flags =
        [
          "-m"
          (toString memory)
          "-netdev"
          "user,id=net0"
          "-device"
          "virtio-net-pci,netdev=net0"
        ]
        ++ lib.optionals (cdrom != null) [
          "-cdrom"
          cdrom
        ]
        ++ lib.optionals (usb != null) [
          "-device"
          "usb-ehci"
          "-drive"
          "id=usbdisk,file=${usb},if=none,readonly"
          "-device"
          "usb-storage,drive=usbdisk"
        ]
        ++ lib.optionals uefi [
          "-drive"
          "if=pflash,format=raw,unit=0,readonly=on,file=${pkgs.OVMF.firmware}"
          "-drive"
          "if=pflash,format=raw,unit=1,readonly=on,file=${pkgs.OVMF.variables}"
        ]
        ++ extraFlags;

      flagsStr = lib.concatStringsSep " " flags;
    in
    "${qemu} ${flagsStr}";

  makeBootTest =
    name: config:
    let
      startCommand = mkStartCommand config;
    in
    pkgs.testers.runNixOSTest {
      name = "boot-${name}";
      nodes = { };
      testScript = ''
        machine = create_machine("${startCommand}")
        machine.start()
        machine.wait_for_unit("multi-user.target")
        machine.succeed("nix store verify --no-trust -r --option experimental-features nix-command /run/current-system")

        machine.shutdown()
      '';
    };
in
{
  uefi-cdrom = makeBootTest "uefi-cdrom" {
    uefi = true;
    cdrom = "${iso}/iso/nixos-installer-${pkgs.stdenv.hostPlatform.system}.iso";
  };

  uefi-usb = makeBootTest "uefi-usb" {
    uefi = true;
    usb = "${iso}/iso/nixos-installer-${pkgs.stdenv.hostPlatform.system}.iso";
  };

  bios-cdrom = makeBootTest "bios-cdrom" {
    cdrom = "${iso}/iso/nixos-installer-${pkgs.stdenv.hostPlatform.system}.iso";
  };

  bios-usb = makeBootTest "bios-usb" {
    usb = "${iso}/iso/nixos-installer-${pkgs.stdenv.hostPlatform.system}.iso";
  };
}
