import json
import sys
import subprocess


def filter_interfaces(network):
    output = []
    for net in network:
        if net["ifname"] == "lo":
            continue
        addr_info = []
        for addr in net["addr_info"]:
            if addr.get("dynamic", False):
                pass
            elif addr["local"].startswith("fe80"):
                pass
            else:
                addr_info.append(addr)
        if addr_info != []:
            net["addr_info"] = addr_info
            output.append(net)

    return output


def main() -> None:
    if len(sys.argv) < 3:
        print(f"USAGE: {sys.argv[0]} addresses routes", file=sys.stderr)
        sys.exit(1)

    with open(sys.argv[1]) as f:
        addresses = json.load(f)
    with open(sys.argv[2]) as f:
        routes = json.load(f)
    relevant_interfaces = filter_interfaces(addresses)
    current_interfaces = json.loads(
        subprocess.run(
            ["ip", "--json", "addr"],
            capture_output=True,
            check=True
        ).stdout
    )

    for interface in relevant_interfaces:
        for current_interface in current_interfaces:
            if "address" in interface and "address" in current_interface:
                if interface["address"] == current_interface["address"]:
                    for addr in interface["addr_info"]:
                        subprocess.run(
                            [
                                "ip",
                                "addr",
                                "add",
                                "dev",
                                current_interface["ifname"],
                                f'{addr["local"]}/{addr["prefixlen"]}',
                            ],
                            check=True
                        )
                    for route in routes:
                        if route["dev"] == interface["ifname"]:
                            if route.get("gateway", False):
                                subprocess.run(
                                    [
                                        "ip",
                                        "route",
                                        "add",
                                        route["dst"],
                                        "via",
                                        route["gateway"],
                                        "dev",
                                        current_interface["ifname"],
                                        "preference",
                                        "1",
                                    ],
                                    check=True
                                )
                            else:
                                subprocess.run(
                                    [
                                        "ip",
                                        "route",
                                        "add",
                                        route["dst"],
                                        "dev",
                                        current_interface["ifname"],
                                        "preference",
                                        "1",
                                    ],
                                    check=True
                                )


if __name__ == "__main__":
    main()
