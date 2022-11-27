import json
import sys
from pathlib import Path
from typing import Any


def filter_interfaces(network: list[dict[str, Any]]) -> list[dict[str, Any]]:
    output = []
    for net in network:
        if net.get("link_type") == "loopback":
            continue
        if not net.get("address"):
            # We need a mac address to match devices reliable
            continue
        addr_info = []
        has_dynamic_address = False
        for addr in net["addr_info"]:
            # no link-local ipv4/ipv6
            if addr.get("scope") == "link":
                continue
            # do not explicitly configure addresses from dhcp or router advertisment
            if addr.get("dynamic", False):
                has_dynamic_address = True
                continue
            else:
                addr_info.append(addr)
        if addr_info != [] or has_dynamic_address:
            net["addr_info"] = addr_info
            output.append(net)

    return output


def filter_routes(routes: list[dict[str, Any]]) -> list[dict[str, Any]]:
    filtered = []
    for route in routes:
        # Filter out routes set by addresses with subnets, dhcp and router advertisment
        if route.get("protocol") in ["dhcp", "kernel", "ra"]:
            continue
        filtered.append(route)

    return filtered


def generate_networkd_units(
    interfaces: list[dict[str, Any]], routes: list[dict[str, Any]], directory: Path
) -> None:
    directory.mkdir(exist_ok=True)
    for interface in interfaces:
        name = f"{interface['ifname']}.network"
        addresses = [
            f"Address = {addr['local']}/{addr['prefixlen']}"
            for addr in interface["addr_info"]
        ]

        route_sections = []
        for route in routes:
            if route["dev"] != interface["ifname"]:
                continue

            route_section = "[Route]"
            if route["dst"] != "default":
                # can be skipped for default routes
                route_section += f"Destination = {route['dst']}\n"
            gateway = route.get("gateway")
            if gateway:
                route_section += f"Gateway = {gateway}\n"

            # we may ignore on-link default routes here, but I don't see how
            # they would be useful for internet connectivity anyway
            route_sections.append(route_section)

        # FIXME in some networks we might not want to trust dhcp or router advertisments
        unit = f"""
[Match]
MACAddress = {interface["address"]}

[Network]
DHCP = yes
IPv6AcceptRA = yes
"""
        unit += "\n".join(addresses)
        unit += "\n" + "\n".join(route_sections)
        (directory / name).write_text(unit)


def main() -> None:
    if len(sys.argv) < 5:
        print(
            f"USAGE: {sys.argv[0]} addresses-v4 addresses-v6 routes-v4 routes-v6 [networkd-directory]",
            file=sys.stderr,
        )
        sys.exit(1)

    with open(sys.argv[1]) as f:
        v4_addresses = json.load(f)
    with open(sys.argv[2]) as f:
        v6_addresses = json.load(f)
    with open(sys.argv[3]) as f:
        v4_routes = json.load(f)
    with open(sys.argv[4]) as f:
        v6_routes = json.load(f)

    if len(sys.argv) >= 5:
        networkd_directory = Path(sys.argv[5])
    else:
        networkd_directory = Path("/etc/systemd/network")

    addresses = v4_addresses + v6_addresses
    relevant_interfaces = filter_interfaces(addresses)
    relevant_routes = filter_routes(v4_routes) + filter_routes(v6_routes)

    generate_networkd_units(relevant_interfaces, relevant_routes, networkd_directory)


if __name__ == "__main__":
    main()
