#!/usr/bin/env python3

import json
import os
import re
import logging
import sys
import shutil
from pathlib import Path
from typing import Any, Iterator
from dataclasses import dataclass


@dataclass
class Address:
    address: str
    family: str
    prefixlen: int
    preferred_life_time: int = 0
    valid_life_time: int = 0


@dataclass
class Interface:
    name: str
    ifname: str | None
    mac_address: str
    dynamic_addresses: list[Address]
    static_addresses: list[Address]
    altnames: list[str]
    static_routes: list[dict[str, Any]]


def filter_networkd_interfaces(networkctl_list: dict[str, Any]) -> list[str]:
    return [
        iface["Name"]
        for iface in networkctl_list["Interfaces"]
        if iface.get("AdministrativeState") == "configured"
    ]


def filter_interfaces(
    network: list[dict[str, Any]], networkd_managed_interfaces: list[str]
) -> list[Interface]:
    interfaces = []
    for net in network:
        if net.get("link_type") == "loopback":
            continue
        if net.get("ifname") in networkd_managed_interfaces:
            continue
        if not (mac_address := net.get("address")):
            # We need a mac address to match devices reliable
            continue
        static_addresses = []
        dynamic_addresses = []
        for info in net.get("addr_info", []):
            # no link-local ipv4/ipv6
            if info.get("scope") == "link":
                continue
            if (preferred_life_time := info.get("preferred_life_time")) is None:
                continue
            if (valid_life_time := info.get("valid_life_time")) is None:
                continue
            if (prefixlen := info.get("prefixlen")) is None:
                continue
            if (family := info.get("family")) not in ["inet", "inet6"]:
                continue
            if (local := info.get("local")) is None:
                continue
            if (dynamic := info.get("dynamic", False)) is None:
                continue

            address = Address(
                address=local,
                family=family,
                prefixlen=prefixlen,
                preferred_life_time=preferred_life_time,
                valid_life_time=valid_life_time,
            )

            if dynamic:
                dynamic_addresses.append(address)
            else:
                static_addresses.append(address)
        interfaces.append(
            Interface(
                name=net.get("ifname", mac_address.replace(":", "-")),
                ifname=net.get("ifname"),
                altnames=net.get("altnames", []),
                mac_address=mac_address,
                dynamic_addresses=dynamic_addresses,
                static_addresses=static_addresses,
                static_routes=[],
            )
        )

    return interfaces


def filter_routes(routes: list[dict[str, Any]]) -> list[dict[str, Any]]:
    filtered = []
    for route in routes:
        # Filter out routes set by addresses with subnets, dhcp and router advertisement
        if route.get("protocol") in ["dhcp", "kernel", "ra"]:
            continue
        filtered.append(route)

    return filtered


def find_most_recent_v4_lease(addresses: list[Address]) -> Address | None:
    most_recent_address = None
    most_recent_lifetime = -1
    for addr in addresses:
        if addr.family == "inet6":
            continue
        lifetime = max(addr.preferred_life_time, addr.valid_life_time)
        if lifetime > most_recent_lifetime:
            most_recent_lifetime = lifetime
            most_recent_address = addr
    return most_recent_address


def generate_routes(
    interface: Interface, routes: list[dict[str, Any]]
) -> Iterator[str]:
    for route in routes:
        if interface.ifname is None or route.get("dev") != interface.ifname:
            continue

        yield "[Route]"
        if route.get("dst") != "default":
            # can be skipped for default routes
            yield f"Destination = {route['dst']}"
        gateway = route.get("gateway")
        # route v4 via v6
        route_via = route.get("via")
        if route_via and route_via.get("family") == "inet6":
            gateway = route_via.get("host")
            if route.get("dst") == "default":
                yield "Destination = 0.0.0.0/0"
        if gateway:
            yield f"Gateway = {gateway}"
        flags = route.get("flags", [])
        if "onlink" in flags:
            yield "GatewayOnLink = yes"


def generate_networkd_units(
    interfaces: list[Interface], routes: list[dict[str, Any]], directory: Path
) -> None:
    directory.mkdir(exist_ok=True)
    for interface in interfaces:
        # FIXME in some networks we might not want to trust dhcp or router advertisements
        unit_sections = [
            f"""
[Match]
MACAddress = {interface.mac_address}

[Network]
# both ipv4 and ipv6
DHCP = yes
# lets us discover the switch port we're connected to
LLDP = yes
# ipv6 router advertisements
IPv6AcceptRA = yes
# allows us to ping "nixos.local"
MulticastDNS = yes"""
        ]
        unit_sections.extend(
            f"Address = {addr.address}/{addr.prefixlen}"
            for addr in interface.static_addresses
        )
        unit_sections.extend(generate_routes(interface, routes))
        most_recent_v4_lease = find_most_recent_v4_lease(interface.dynamic_addresses)
        if most_recent_v4_lease:
            unit_sections.append("[DHCPv4]")
            unit_sections.append(f"RequestAddress = {most_recent_v4_lease.address}")

        # trailing newline at the end
        unit_sections.append("")

        (directory / f"00-{interface.name}.network").write_text(
            "\n".join(unit_sections)
        )


def file_inplace_regex(file_path: str, pattern: str, new_text: str):
    with open(file_path, "r", encoding="utf-8") as file:
        file_contents = file.read()
    modified_contents = re.sub(pattern, new_text, file_contents)
    with open(file_path, "w", encoding="utf-8") as file:
        file.write(modified_contents)


def handover_networkd_conf(
    src: Path,
    dest: Path,
    ip_a_json: list[dict[str, Any]],
    networkd_managed_interfaces: list[str],
) -> None:
    dest.mkdir(parents=True, exist_ok=True)
    ip_a_interfaces = filter_interfaces(ip_a_json, [])

    for iface in networkd_managed_interfaces:
        # hanlde unpredictable interface names from host
        # kexec-installer use predictable names
        if iface.startswith("eth"):
            ip_a_iface = next(i for i in ip_a_interfaces if i.ifname == iface)

            src_path = f"{src}/00-{iface}.network"
            if not os.path.isfile(src_path):
                continue

            if ip_a_iface.altnames != []:
                file_inplace_regex(
                    src_path, f"Name={iface}", f"Name={ip_a_iface.altnames[0]}"
                )
            else:
                file_inplace_regex(
                    src_path, f"Name={iface}", f"MACAddress={ip_a_iface.mac_address}"
                )

        for conftype in ["netdev", "network", "link"]:
            src_path = f"{src}/00-{iface}.{conftype}"
            if os.path.isfile(src_path):
                shutil.copy2(src_path, dest)


def main() -> None:
    if len(sys.argv) < 7:
        print(
            f"USAGE: {sys.argv[0]} addresses routes-v4 routes-v6 networkctl-list networkd-ifaces-directory networkd-output-directory",
            file=sys.stderr,
        )
        sys.exit(1)

    with open(sys.argv[1]) as f:
        addresses = json.load(f)
    with open(sys.argv[2]) as f:
        v4_routes = json.load(f)
    with open(sys.argv[3]) as f:
        v6_routes = json.load(f)
    try:
        with open(sys.argv[4]) as f:
            networkctl_list = json.load(f)
    except FileNotFoundError as e:
        logging.debug(f"could not load networkctl json from {sys.argv[4]}: {e}")
        networkctl_list = {}
    except Exception as e:
        raise e
    host_networkd_iface_directory = Path(sys.argv[5])
    networkd_directory = Path(sys.argv[6])

    # networkd
    networkd_managed_interfaces = []
    if networkctl_list != {}:
        networkd_managed_interfaces = filter_networkd_interfaces(networkctl_list)
        handover_networkd_conf(
            host_networkd_iface_directory,
            networkd_directory,
            addresses,
            networkd_managed_interfaces,
        )

    # iproute2
    relevant_interfaces = filter_interfaces(addresses, networkd_managed_interfaces)
    relevant_routes = filter_routes(v4_routes) + filter_routes(v6_routes)
    generate_networkd_units(relevant_interfaces, relevant_routes, networkd_directory)


if __name__ == "__main__":
    main()
