#!/usr/bin/env python3

from dataclasses import dataclass
import json
import subprocess
import time
import sys
import logging
from typing import Any, Dict


MAX_WAIT_SECONDS = 60 * 4
CHECK_INTERVAL_SECONDS = 3


@dataclass
class Address:
    dynamic: bool
    address: str
    family: str
    prefixlen: int


@dataclass
class InterfaceInfo:
    altnames: set[str]
    addresses: list[Address]
    mac_address: str | None
    unpredictable: bool


Interfaces = Dict[str, InterfaceInfo]


def interfaces_current_get() -> set[str]:
    result = subprocess.run(
        ["ip", "-json", "link", "show"],
        capture_output=True,
        text=True,
        check=True,
    )
    data = json.loads(result.stdout)
    return {iface["ifname"] for iface in data}


def ifname_from_mac(mac_address: str) -> str:
    return f"enx{mac_address.replace(':', '')}"


def interfaces_with_dynamic_addr(
    iproute2_addr: list[dict[str, Any]],
) -> Interfaces:
    ifaces: Interfaces = {}
    for entry in iproute2_addr:
        ifname: str = entry.get("ifname", "")
        if not ifname:
            continue

        altnames: set[str] = set(entry.get("altnames", []))
        mac_address: str | None = entry.get("address")
        # handle unpredictable interface names
        # we dont negotiate with unpredictable names
        unpredictable = False
        if ifname.startswith("eth"):
            unpredictable = True
            if mac_address is not None:
                altnames.add(ifname_from_mac(mac_address))

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
        ifaces[ifname] = InterfaceInfo(
            unpredictable=unpredictable,
            altnames=entry.get("altnames", []),
            addresses=addresses,
            mac_address=mac_address,
        )

    return {
        key: value
        for key, value in ifaces.items()
        if value.addresses != []
    }


def interface_restore(iface_name: str, iface_info: InterfaceInfo):
    ifname_used = iface_name
    if iface_info.unpredictable and iface_info.mac_address is not None:
        ifname_used = ifname_from_mac(iface_info.mac_address)

    for addr in iface_info.addresses:
        cmd = [
            "ip",
            "addr",
            "add",
            f"{addr.address}/{addr.prefixlen}",
            "dev",
            ifname_used,
            "preferred_lft",
            "0",
        ]
        try:
            subprocess.run(cmd, check=True, capture_output=True, text=True)
            logging.info(f"    Restored {addr}")
        except subprocess.CalledProcessError as e:
            logging.warning(
                f"    Failed Address restore, {''.join(cmd)},{e.stderr.strip()}"
            )


def main():
    logging.basicConfig(level=logging.INFO)

    with open(sys.argv[1], "r", encoding="utf-8") as f:
        iproute2_addr = json.load(f)

    ifaces = interfaces_with_dynamic_addr(iproute2_addr)
    if ifaces == {}:
        logging.info("No interfaces with dynamic IP address found in JSON")
        return 0

    start_time = time.monotonic()
    while True:
        logging.info("Waiting for these interfaces to appear")
        for iface in ifaces:
            logging.info(f"    {iface}:{ifaces[iface]}")

        current_ifaces = interfaces_current_get()
        for iface in list(ifaces.keys()):
            iface_all_names = ifaces[iface].altnames
            if not ifaces[iface].unpredictable:
                iface_all_names.add(iface)
            if len(set(current_ifaces) & set(iface_all_names)) == 0:
                continue

            interface_restore(iface, ifaces[iface])
            del ifaces[iface]

        elapsed = time.monotonic() - start_time
        if elapsed > MAX_WAIT_SECONDS:
            logging.error(f"Timeout after {MAX_WAIT_SECONDS}s waitig for")
            for iface in ifaces:
                logging.info(f"     {iface}:{ifaces[iface]}")
            return 1
        else:
            if ifaces == {}:
                break
            time.sleep(CHECK_INTERVAL_SECONDS)

    logging.info("Finished. Successfully restored dynamic addresses")
    return 0


def usage_print():
    print(f"Usage: {sys.argv[0]} iproute2_addr.json")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        usage_print()
        sys.exit(1)
    elif sys.argv[1] in ("-h", "--help"):
        usage_print()
        sys.exit(0)
    else:
        sys.exit(main())
