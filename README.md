# nixos-images

Automatically weekly updated images for NixOS. This project is intended to extend the images created by hydra.nixos.org.
We are currently creating the images listed below:

## Kexec tarballs

These images are used for unattended remote installation in [nixos-anywhere](https://github.com/numtide/nixos-anywhere).

Kexec is a mechanism in Linux to load a new kernel from a running Linux to
replace the current kernel. This is useful for booting the Nixos installer from
existing Linux distributions, such as server provider that do not offer a NixOS
option. After running kexec, the NixOS installer exists only in memory. At the
time of writing, this requires at least 1GB of physical RAM (swap does not
count) in the system. If not enough RAM is available, the initrd cannot be
loaded. Because the NixOS runs only in RAM, users can reformat all the system's
discs to prepare for a new NixOS installation.

It can be booted as follows by running these commands as root:

```
curl -L https://github.com/nix-community/nixos-images/releases/download/nixos-unstable/nixos-kexec-installer-noninteractive-x86_64-linux.tar.gz | tar -xzf- -C /root
/root/kexec/run
```

The kexec installer comes with the following features:

- Re-uses ssh host keys from the sshd to not break `.ssh/known_hosts`
- Authorized ssh keys are read from `/root/.ssh/authorized_keys`, `/root/.ssh/authorized_keys2` and `/etc/ssh/authorized_keys.d/root`
- Static ip addresses and routes are restored after reboot.
  Interface that had dynamic addresses before are configured with DHCP and
  to accept prefixes from ipv6 router advertisement

The actual kexec happens with a slight delay (6s). This allows for easier
integration into automated nixos installation scripts, since you can cleanly
disconnect from the running machine before the kexec takes place. The tarball
is also designed to be run from NixOS, which can be useful for new installations

## ISO installer images

This image allows to boot a NixOS installer off a USB-Stick.
This installer has been optimized for remote installation i.e.
with [nixos-anywhere](https://github.com/numtide/nixos-anywhere) and [clan](https://docs.clan.lol/getting-started/installer/) notably:

* Enables openssh by default
* Generates a random root password on each login
* Enables a Tor hidden SSH service so that by using the `torify ssh <hash>.onion`,
  one can log in from remote machines.
* Prints a QR-Code that contains local addresses, the root password
* Includes the [IWD](https://wiki.archlinux.org/title/iwd) deamon for easier wifi setups:
  * Run `iwctl` in the terminal for an interactive wifi setup interface.

![Screenshot of the installer](https://github.com/nix-community/nixos-images/releases/download/assets/image-installer-screenshot.jpg)

## Netboot images

You can boot the netboot image using this [ipxe script](https://github.com/nix-community/nixos-images/releases/download/nixos-unstable/netboot-x86_64-linux.ipxe).
It consists of the [kernel image](https://github.com/nix-community/nixos-images/releases/download/nixos-unstable/bzImage-x86_64-linux) and [initrd](https://github.com/nix-community/nixos-images/releases/download/nixos-unstable/initrd-x86_64-linux).
