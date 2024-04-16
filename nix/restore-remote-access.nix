{
  # Restore ssh host and user keys if they are available.
  # This avoids warnings of unknown ssh keys.
  boot.initrd.postMountCommands = ''
    mkdir -m 700 -p /mnt-root/root/.ssh
    mkdir -m 755 -p /mnt-root/etc/ssh
    mkdir -m 755 -p /mnt-root/root/network
    if [[ -f ssh/authorized_keys ]]; then
      install -m 400 ssh/authorized_keys /mnt-root/root/.ssh
    fi
    install -m 400 ssh/ssh_host_* /mnt-root/etc/ssh
    cp *.json /mnt-root/root/network/
    if [[ -f machine-id ]]; then
      cp machine-id /mnt-root/etc/machine-id
    fi
  '';
}
