#!/bin/sh

# Set pipefail if the shell supports it.
if set -o | grep -q pipefail; then
  # shellcheck disable=SC3040
  set -o pipefail
fi
set -eux


kexec_extra_flags=""

while [ $# -gt 0 ]; do
  case "$1" in
  --kexec-extra-flags)
    kexec_extra_flags="$2"
    shift
    ;;
  esac
  shift
done

# provided by nix
init="@init@"
kernelParams="@kernelParams@"

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
INITRD_TMP=$(TMPDIR=$SCRIPT_DIR mktemp -d)

cd "$INITRD_TMP"
cleanup() {
  rm -rf "$INITRD_TMP"
}
trap cleanup EXIT
mkdir -p ssh

extractPubKeys() {
  home="$1"
  for file in .ssh/authorized_keys .ssh/authorized_keys2; do
    key="$home/$file"
    if test -e "$key"; then
      # workaround for debian shenanigans
      grep -o '\(\(ssh\|ecdsa\|sk\)-[^ ]* .*\)' "$key" >> ssh/authorized_keys || true
    fi
  done
}
extractPubKeys /root

if test -n "${DOAS_USER-}"; then
  SUDO_USER="$DOAS_USER"
fi

if test -n "${SUDO_USER-}"; then
  sudo_home=$(sh -c "echo ~$SUDO_USER")
  extractPubKeys "$sudo_home"
fi

# Typically for NixOS
if test -e /etc/ssh/authorized_keys.d/root; then
  cat /etc/ssh/authorized_keys.d/root >> ssh/authorized_keys
fi
if test -n "${SUDO_USER-}" && test -e "/etc/ssh/authorized_keys.d/$SUDO_USER"; then
  cat "/etc/ssh/authorized_keys.d/$SUDO_USER" >> ssh/authorized_keys
fi
for p in /etc/ssh/ssh_host_*; do
  test -e "$p" || continue
  cp -a "$p" ssh
done

# save the networking config for later use
"$SCRIPT_DIR/ip" --json addr > addrs.json

"$SCRIPT_DIR/ip" -4 --json route > routes-v4.json
"$SCRIPT_DIR/ip" -6 --json route > routes-v6.json

[ -f /etc/machine-id ] && cp /etc/machine-id machine-id

find . | cpio -o -H newc | gzip -9 >> "$SCRIPT_DIR/initrd"

kexecSyscallFlags=""
# only do kexec-syscall-auto on kernels newer than 6.0.
# On older kernel we often get errors like: https://github.com/nix-community/nixos-anywhere/issues/264
if printf "%s\n" "6.1" "$(uname -r)" | sort -c -V 2>&1; then
  kexecSyscallFlags="--kexec-syscall-auto"
fi

if ! sh -c "'$SCRIPT_DIR/kexec' --load '$SCRIPT_DIR/bzImage' \
  $kexecSyscallFlags \
  $kexec_extra_flags \
  --initrd='$SCRIPT_DIR/initrd' --no-checks \
  --command-line 'init=$init $kernelParams'"
then
  echo "kexec failed, dumping dmesg"
  dmesg | tail -n 100
  exit 1
fi

# Disconnect our background kexec from the terminal
echo "machine will boot into nixos in 6s..."
if test -e /dev/kmsg; then
  # this makes logging visible in `dmesg`, or the system console or tools like journald
  exec > /dev/kmsg 2>&1
else
  exec > /dev/null 2>&1
fi
# We will kexec in background so we can cleanly finish the script before the hosts go down.
# This makes integration with tools like terraform easier.
nohup sh -c "sleep 6 && '$SCRIPT_DIR/kexec' -e ${kexec_extra_flags}" &
