#!/usr/bin/env python3

from dataclasses import dataclass
import json
import subprocess
import time
import sys
import logging
from typing import Any

MAX_WAIT_SECONDS = 60 * 4
CHECK_INTERVAL_SECONDS = 3


@dataclass
class Address:
    dynamic: bool
    address: str
    family: str
    prefixlen: int


@dataclass
class Interface:
    name: str
    altnames: list[str]
    addresses: list[Address]


def interfaces_current_get() -> set[str]:
    result = subprocess.run(
        ["ip", "-json", "link", "show"],
        capture_output=True,
        text=True,
        check=True,
    )
    data = json.loads(result.stdout)
    return {iface["ifname"] for iface in data}


def interface_exists(ifname: str) -> bool:
    return ifname in interfaces_current_get()


def interfaces_with_dynamic_addr(
    iproute2_addr: list[dict[str, Any]],
) -> list[Interface]:
    required_ifaces: list[Interface] = []
    for entry in iproute2_addr:
        ifname: str = entry.get("ifname", "")
        if not ifname:
            continue

        # handle unpredictable interface names
        if ifname.startswith("eth"):
            mac_address: str = entry.get("address", "")
            if not mac_address:
                continue
            ifname = f"enx{mac_address.replace(':', '')}"

        has_dynamic = any(a.get("dynamic", False) for a in entry.get("addr_info", []))
        if not has_dynamic:
            continue

        addresses: list[Address] = []
        for info in entry.get("addr_info", []):
            if not info.get("dynamic", False):
                continue
            if (prefixlen := info.get("prefixlen")) is None:
                continue
            if (family := info.get("family")) not in [
                "inet",
                "inet6",
            ]:
                continue
            if (local := info.get("local")) is None:
                continue

            addresses.append(
                Address(
                    address=local,
                    family=family,
                    prefixlen=prefixlen,
                    dynamic=True,
                )
            )
        required_ifaces.append(
            Interface(
                name=ifname,
                altnames=entry.get("altnames", []),
                addresses=addresses,
            )
        )

    return required_ifaces


def interface_addr_add(iface: Interface):
    for addr in iface.addresses:
        cmd = [
            "ip",
            "addr",
            "add",
            f"{addr.address}/{addr.prefixlen}",
            "dev",
            iface.name,
            "preferred_lft",
            "0",
        ]
        try:
            subprocess.run(cmd, check=True, capture_output=True, text=True)
            logging.info(f"    Restored {addr}")
        except subprocess.CalledProcessError as e:
            logging.warning(f"    Failed interface restore, {e.stderr.strip()}")


def main():
    logging.basicConfig(level=logging.INFO)

    with open(sys.argv[1]) as f:
        iproute2_addr = json.load(f)

    required_ifaces = interfaces_with_dynamic_addr(iproute2_addr)
    if not required_ifaces:
        logging.info("No interfaces with dynamic IP addresses found in JSON")
        return 0

    start_time = time.monotonic()
    while True:
        logging.info("Waiting for these interfaces to appear")
        for iface in required_ifaces:
            logging.info(f"    {iface}")

        current_ifaces = interfaces_current_get()
        for iface in required_ifaces:
            if len(set(current_ifaces) & set(iface.altnames + [iface.name])) == 0:
                continue

            interface_addr_add(iface)
            required_ifaces.remove(iface)

        elapsed = time.monotonic() - start_time
        if elapsed > MAX_WAIT_SECONDS:
            logging.error(f"Timeout after {MAX_WAIT_SECONDS}s waitig for")
            for iface in required_ifaces:
                logging.info(f"     {iface}")
            return 1
        else:
            if required_ifaces == []:
                break
            time.sleep(CHECK_INTERVAL_SECONDS)

    logging.info("Finished. Successfully restored dynamic addresses")
    return 0


def usage_print():
    print(f"Usage: {sys.argv[0]} iproute2_addr.json")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        usage_print()
        sys.exit(len(sys.argv) > 2)
    if sys.argv[1] in ("-h", "--help"):
        usage_print()
        sys.exit(0)

    sys.exit(main())
