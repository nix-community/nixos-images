# nixos-images

Automatically weekly updated images for NixOS. This project is intended to extend the images created by hydra.nixos.org.
We are currently creating the images listed below:

## Netboot images

You can boot the netboot image using this [ipxe script](https://github.com/nix-community/nixos-images/releases/download/nixos-unstable/netboot-x86_64-linux.ipxe).
It consists of the [kernel image](https://github.com/nix-community/nixos-images/releases/download/nixos-unstable/bzImage-x86_64-linux) and [initrd](https://github.com/nix-community/nixos-images/releases/download/nixos-unstable/bzImage-x86_64-linux).

## Kexec tarballs

Kexec is a mechanism in Linux to load a new kernel from a running Linux to
replace the current kernel. This is useful for booting the Nixos installer from
existing Linux distributions, such as server provider that do not offer a NixOS
option. After running kexec, the NixOS installer exists only in memory. At the
time of writing, this requires at least 2.5GB of physical RAM (swap does not
count) in the system. If not enough RAM is available, the initrd cannot be
loaded. Because the NixOS runs only in RAM, users can reformat all the system's
discs to prepare for a new NixOS installation.

It can be booted as follows by running these commands as root:

```
curl -L https://github.com/nix-community/nixos-images/releases/download/nixos-unstable/nixos-kexec-installer-x86_64-linux.tar.gz | tar -xzf- -C /root
/root/kexec/run
```

The kexec installer comes with the following features:

- Re-uses ssh host keys from the sshd to not break `.ssh/known_hosts`
- Authorized ssh keys are read from `/root/.ssh/authorized_keys`, `/root/.ssh/authorized_keys2` and `/etc/ssh/authorized_keys.d/root`
- (experimental, only tested for nixos-unstable) Static ip addresses and routes
  are restored after reboot. Interface that had dynamic addresses before are
  configured with DHCP and to accept prefixes from ipv6 router advertisment


The actual kexec happens with a slight delay (6s).  This allows for easier
integration into automated nixos installation scripts, since you can cleanly
disconnect from the running machine before the kexec takes place.  The tarball
is also designed to be run from NixOS, which can be useful for new installations
