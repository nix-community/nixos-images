import json
import sys
from pathlib import Path
from typing import Any, Iterator
from dataclasses import dataclass


@dataclass
class Interface:
    name: str
    ifname: str | None
    mac_address: str
    dynamic_addresses: list[str]
    static_addresses: list[dict[str, Any]]
    static_routes: list[dict[str, Any]]


def filter_interfaces(network: list[dict[str, Any]]) -> list[Interface]:
    interfaces = []
    for net in network:
        if net.get("link_type") == "loopback":
            continue
        if not (mac_address := net.get("address")):
            # We need a mac address to match devices reliable
            continue
        static_addresses = []
        dynamic_addresses = []
        for addr in net.get("addr_info", []):
            # no link-local ipv4/ipv6
            if addr.get("scope") == "link":
                continue
            if addr.get("dynamic", False):
                dynamic_addresses.append(addr["local"])
            else:
                static_addresses.append(addr)
        interfaces.append(
            Interface(
                name=net.get("ifname", mac_address.replace(":", "-")),
                ifname=net.get("ifname"),
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


def generate_routes(
    interface: Interface, routes: list[dict[str, Any]]
) -> Iterator[str]:
    for route in routes:
        if interface.ifname is None or route.get("dev") != interface.ifname:
            continue

        # we may ignore on-link default routes here, but I don't see how
        # they would be useful for internet connectivity anyway

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
MulticastDNS = yes
"""
        ]
        unit_sections.extend(
            f"Address = {addr['local']}/{addr['prefixlen']}"
            for addr in interface.static_addresses
        )
        unit_sections.extend(generate_routes(interface, routes))

        (directory / f"00-{interface.name}.network").write_text("\n".join(unit_sections))


def main() -> None:
    if len(sys.argv) < 5:
        print(
            f"USAGE: {sys.argv[0]} addresses routes-v4 routes-v6 networkd-directory",
            file=sys.stderr,
        )
        sys.exit(1)

    with open(sys.argv[1]) as f:
        addresses = json.load(f)
    with open(sys.argv[2]) as f:
        v4_routes = json.load(f)
    with open(sys.argv[3]) as f:
        v6_routes = json.load(f)

    networkd_directory = Path(sys.argv[4])

    relevant_interfaces = filter_interfaces(addresses)
    relevant_routes = filter_routes(v4_routes) + filter_routes(v6_routes)

    generate_networkd_units(relevant_interfaces, relevant_routes, networkd_directory)


if __name__ == "__main__":
    main()
