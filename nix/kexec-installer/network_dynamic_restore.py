#!/usr/bin/env python3

from dataclasses import dataclass
import json
import re
import subprocess
import time
import sys
import logging
from typing import Any, Dict, TextIO


MAX_WAIT_SECONDS = 60 * 4
CHECK_INTERVAL_SECONDS = 3
ROUTE_METRIC_MAX = (1 << 32) - 1


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
    routes: list[str]
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


def interface_exists(ifname: str) -> bool:
    return ifname in interfaces_current_get()


def routes_parse_dynamic(iproute2_route: TextIO) -> Dict[str, list[str]]:
    result: Dict[str, list[str]] = {}

    for line in iproute2_route:
        line = line.strip()
        if not line:
            continue
        if not re.search(r"\bproto\s+(dhcp|ra)\b", line):
            continue

        # set lowest metric
        modified = re.sub(r"\bmetric\s+\d+\b", "metric 4294967295", line)
        # using next hop spec, no need for next hop id
        modified = re.sub(r"\bnhid\s+\d+\b", "", modified)
        # cleanup expires
        modified = re.sub(
            r"expires\s*(\d+)sec\b", lambda m: f"expires {m.group(1)}", modified
        )

        ifname_match = re.search(r"\bdev\s+([^\s]+)", modified)
        if not ifname_match:
            continue
        ifname = ifname_match.group(1)
        if ifname not in result:
            result[ifname] = []
        result[ifname].append(modified)

    return result


def ifname_from_mac(mac_address: str) -> str:
    return f"enx{mac_address.replace(':', '')}"


def interfaces_with_dynamic_addr_or_routes(
    iproute2_addr: list[dict[str, Any]],
    iproute2_route: TextIO,
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
            routes=[],
        )

        routes = routes_parse_dynamic(iproute2_route)
        for key in routes:
            ifaces[key].routes = routes[key]

    return {
        key: value
        for key, value in ifaces.items()
        if value.addresses != [] or value.routes != []
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

    for route in iface_info.routes:
        route = re.sub(r"\bdev\s+([^\s]+)", f"dev {ifname_used}", route)
        route = "ip route add " + route

        try:
            subprocess.run(route.split(), check=True, capture_output=True, text=True)
            logging.info(f"    Restored Route with {route}")
        except subprocess.CalledProcessError as e:
            logging.warning(f"    Failed Route restore, {route}, {e.stderr.strip()}")


def main():
    logging.basicConfig(level=logging.INFO)

    with open(sys.argv[1], "r", encoding="utf-8") as f:
        iproute2_addr = json.load(f)
    iproute2_route = open(sys.argv[2], "r", encoding="utf-8")

    ifaces = interfaces_with_dynamic_addr_or_routes(iproute2_addr, iproute2_route)
    if ifaces == {}:
        logging.info("No interfaces with dynamic IP addresses/routes found in JSON")
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
    print(f"Usage: {sys.argv[0]} iproute2_addr.json iproute2_route")


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] in ("-h", "--help"):
        usage_print()
        sys.exit(0)

    if len(sys.argv) != 3:
        usage_print()
        sys.exit(1)

    sys.exit(main())
