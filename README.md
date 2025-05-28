# nixos-images

This project provides automatically updated NixOS images that complement the official images from hydra.nixos.org. New images are built weekly to ensure you always have access to the latest NixOS features and security updates.

## Available Image Types

We currently offer three types of NixOS images:

- **[ISO Installer Images](#iso-installer-images)**: Bootable USB images for installing NixOS on physical hardware
- **[Kexec Tarballs](#kexec-tarballs)**: For booting NixOS installer from an existing Linux system
- **[Netboot Images](#netboot-images)**: For booting NixOS over the network via PXE/iPXE

## ISO Installer Images

Our ISO installer images allow you to boot NixOS from a USB drive. These images have been optimized for both local and remote installations.

### Creating a Bootable NixOS USB Drive

#### Step 1: Download the ISO image

Choose the appropriate image for your system architecture:

**For x86_64 (64-bit Intel/AMD):**
```bash
wget https://github.com/nix-community/nixos-images/releases/download/nixos-unstable/nixos-installer-x86_64-linux.iso
```

**For aarch64 (64-bit ARM):**
```bash
wget https://github.com/nix-community/nixos-images/releases/download/nixos-unstable/nixos-installer-aarch64-linux.iso
```

You can also download the images directly from the [releases page](https://github.com/nix-community/nixos-images/releases).

#### Step 2: Identify your USB drive

**On Linux:**
```bash
lsblk
```

**On macOS:**
```bash
diskutil list
```

Make careful note of the device name (e.g., `/dev/sdb`, `/dev/disk2`, etc.) - **writing to the wrong device can cause data loss!**

#### Step 4: Write the ISO to the USB drive

**On Linux:**
```bash
# Replace /dev/sdX with your USB drive device
sudo dd if=nixos-installer-x86_64-linux.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

**On macOS:**
```bash
# First unmount the drive (replace N with your disk number)
diskutil unmountDisk /dev/diskN

# Write the image (replace N with your disk number)
sudo dd if=nixos-installer-x86_64-linux.iso of=/dev/rdiskN bs=1m
```

**On Windows:**
We recommend using tools like [Rufus](https://rufus.ie/), [balenaEtcher](https://www.balena.io/etcher/), or [Ventoy](https://www.ventoy.net/) to write the ISO:
1. Download and run one of these tools
2. Select the downloaded ISO file
3. Select your USB drive (the tool will show available drives)
4. Start the writing process

#### Step 5: Boot from the USB drive

1. Insert the USB drive into the target computer
2. Restart the computer
3. **Disable Secure Boot in BIOS/UEFI** (NixOS installer currently requires Secure Boot to be disabled)
4. Enter the boot menu (usually by pressing F12, F2, or Del during startup)
5. Select the USB drive as the boot device

### Special Features of the NixOS Installer

Our installer has been optimized for both local and remote installations (like with [nixos-anywhere](https://github.com/numtide/nixos-anywhere) and [clan](https://docs.clan.lol/getting-started/installer/)):

* **SSH Access**: OpenSSH server is enabled by default for remote installations
* **Security**: A random root password is generated on each boot
* **Remote Access via Tor**: A Tor hidden SSH service is enabled, allowing access via `torify ssh <hash>.onion`
* **Easy Configuration**: A QR code is displayed that contains local addresses and the root password
* **Simplified WiFi Setup**: Includes [IWD](https://wiki.archlinux.org/title/iwd) daemon:
  * Run `iwctl` in the terminal for an interactive WiFi setup interface
  * Use `iwctl station list` to list WiFi adapters
  * Use `iwctl station <adapter> scan` to scan for networks
  * Use `iwctl station <adapter> connect <SSID>` to connect

### What's Next?

After booting the installer, you can:
1. Use [disko](https://github.com/nix-community/disko) for declarative disk partitioning
2. Follow the [NixOS manual](https://nixos.org/manual/nixos/stable/) for installation
3. Use [nixos-anywhere](https://github.com/numtide/nixos-anywhere) for automated installation

![Screenshot of the installer](https://github.com/nix-community/nixos-images/releases/download/assets/image-installer-screenshot.jpg)


## Kexec Tarballs

Kexec tarballs provide a way to boot the NixOS installer directly from an existing Linux system without requiring physical media or rebooting.

### What is Kexec?

Kexec is a mechanism in Linux that allows you to load and boot a new kernel from within a currently running Linux system. This is particularly useful for:

- **Remote server installations** where you don't have physical access
- **Cloud providers** that don't offer NixOS as an installation option
- **Quick system reinstalls** without needing to create bootable media

### Requirements

- Secure Boot must be disabled in BIOS/UEFI
- At least 1GB of physical RAM (swap does not count)
- Root access on the existing Linux system

### Using the Kexec Installer

#### Step 1: Download and Run the Installer

Run these commands as root on your existing Linux system:

```bash
curl -L https://github.com/nix-community/nixos-images/releases/latest/download/nixos-kexec-installer-noninteractive-x86_64-linux.tar.gz | tar -xzf- -C /root
/root/kexec/run
```

After executing these commands, there will be a short delay (6 seconds) before the kexec process replaces your current kernel with the NixOS installer kernel. This delay allows you to disconnect cleanly if running the commands over SSH.

#### What Happens Next?

- Your system will boot into a minimal NixOS installer environment
- The installer runs entirely in RAM, allowing you to reformat all disks
- Your previous system is no longer accessible until you reboot

### Special Features

The kexec installer includes several features to make remote installation easier:

- **SSH Host Key Preservation**: Reuses SSH host keys from the existing system to prevent breaking `.ssh/known_hosts` on client machines
- **SSH Key Authorization**: Automatically imports authorized keys from:
  - `/root/.ssh/authorized_keys`
  - `/root/.ssh/authorized_keys2`
  - `/etc/ssh/authorized_keys.d/root`
- **Network Configuration Preservation**: Maintains static IP addresses and routes from your previous system
  - Interfaces with dynamic addresses are configured to use DHCP
  - IPv6 router advertisement is enabled for prefix delegation

### Automated Installation

The kexec installer is designed to work seamlessly with [nixos-anywhere](https://github.com/numtide/nixos-anywhere) for fully automated NixOS installations.

## Netboot Images

Netboot images allow you to boot NixOS over the network without requiring local installation media.

### What is Netboot?

Network booting (netboot) enables computers to boot and load an operating system from the network rather than from local storage. This is useful for:

- **Diskless workstations** that run entirely from network resources
- **PXE boot environments** in data centers or computer labs
- **Remote installations** where physical media is not available
- **Testing and development** environments that need clean systems

### Components

Our netboot package consists of three main components:

1. **iPXE Script**: A configuration file that tells the network boot client what to load
2. **Kernel Image**: The Linux kernel that will be booted
3. **Initial RAM Disk (initrd)**: Contains the essential files needed to boot NixOS

### Using Netboot Images

#### Option 1: Direct iPXE Boot

If you already have an iPXE environment set up, you can use our prepared iPXE script:

```bash
# Boot directly using our iPXE script
chain https://github.com/nix-community/nixos-images/releases/download/nixos-unstable/netboot-x86_64-linux.ipxe
```

#### Option 2: Manual Configuration

If you're setting up your own PXE/TFTP server, you'll need:

1. **Kernel**: [bzImage-x86_64-linux](https://github.com/nix-community/nixos-images/releases/download/nixos-unstable/bzImage-x86_64-linux)
2. **Initial RAM Disk**: [initrd-x86_64-linux](https://github.com/nix-community/nixos-images/releases/download/nixos-unstable/initrd-x86_64-linux)

Configure your DHCP server to point to your TFTP server, and configure the TFTP server to serve these files.

### Server Configuration Example

Here's a basic example for setting up a TFTP/PXE server with dnsmasq:

```bash
# Create a temporary environment with dnsmasq
nix-shell -p dnsmasq

# Create a configuration file
cat > dnsmasq.conf << EOF
interface=eth0
dhcp-range=192.168.1.100,192.168.1.150,12h
dhcp-boot=pxelinux.0
enable-tftp
tftp-root=/srv/tftp
EOF

# Create the TFTP directory
mkdir -p /srv/tftp/nixos

# Download the netboot files
curl -o /srv/tftp/nixos/bzImage https://github.com/nix-community/nixos-images/releases/download/nixos-unstable/bzImage-x86_64-linux
curl -o /srv/tftp/nixos/initrd https://github.com/nix-community/nixos-images/releases/download/nixos-unstable/initrd-x86_64-linux

# Run dnsmasq
dnsmasq --conf-file=dnsmasq.conf --no-daemon
```

### Further Resources

For more detailed information on network booting:

- [NixOS Netboot Documentation](https://wiki.nixos.org/wiki/Netboot)
- [iPXE Documentation](https://ipxe.org/start)
