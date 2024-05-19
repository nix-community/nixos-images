#!/usr/bin/env bash

# filter_interfaces function
filter_interfaces() {
    # This function takes a list of network interfaces as input and filters
    # out loopback interfaces, interfaces without a MAC address, and addresses
    # with a "link" scope or marked as dynamic (from DHCP or router
    # advertisements). The filtered interfaces are returned one by one on stdout.
    local network=("$@")

    for net in "${network[@]}"; do
        local link_type="$(jq -r '.link_type' <<< "$net")"
        local address="$(jq -r '.address // ""' <<< "$net")"
        local addr_info="$(jq -r '.addr_info | map(select(.scope != "link" and (.dynamic | not)))' <<< "$net")"
        local has_dynamic_address=$(jq -r '.addr_info | any(.dynamic)' <<< "$net")

        # echo "Link Type: $link_type -- Address: $address -- Has Dynamic Address: $has_dynamic_address  -- Addr Info: $addr_info"

        if [[ "$link_type" != "loopback" && -n "$address" && ("$addr_info" != "[]" || "$has_dynamic_address" == "true") ]]; then
            net=$(jq -c --argjson addr_info "$addr_info" '.addr_info = $addr_info' <<< "$net")
            echo "$net" # "return"
        fi
    done
}

# filter_routes function
filter_routes() {
    # This function takes a list of routes as input and filters out routes
    # with protocols "dhcp", "kernel", or "ra". The filtered routes are
    # returned one by one on stdout.
    local routes=("$@")

    for route in "${routes[@]}"; do
        local protocol=$(jq -r '.protocol' <<< "$route")
        if [[ $protocol != "dhcp" && $protocol != "kernel" && $protocol != "ra" ]]; then
            echo "$route" # "return"
        fi
    done
}

# generate_networkd_units function
generate_networkd_units() {
    # This function takes the filtered interfaces and routes, along with a
    # directory path. It generates systemd-networkd unit files for each interface,
    # including the configured addresses and routes. The unit files are written
    # to the specified directory with the naming convention 00-<ifname>.network.
    local -n interfaces=$1
    local -n routes=$2
    local directory="$3"

    mkdir -p "$directory"

    for interface in "${interfaces[@]}"; do
        local ifname=$(jq -r '.ifname' <<< "$interface")
        local address=$(jq -r '.address' <<< "$interface")
        local addresses=$(jq -r '.addr_info | map("Address = \(.local)/\(.prefixlen)") | join("\n")' <<< "$interface")
        local route_sections=()

        for route in "${routes[@]}"; do
            local dev=$(jq -r '.dev' <<< "$route")
            if [[ $dev == $ifname ]]; then
                local route_section="[Route]"
                local dst=$(jq -r '.dst' <<< "$route")
                if [[ $dst != "default" ]]; then
                    route_section+="\nDestination = $dst"
                fi
                local gateway=$(jq -r '.gateway // ""' <<< "$route")
                if [[ -n $gateway ]]; then
                    route_section+="\nGateway = $gateway"
                fi
                route_sections+=("$route_section")
            fi
        done

        local unit=$(cat <<-EOF
[Match]
MACAddress = $address

[Network]
DHCP = yes
LLDP = yes
IPv6AcceptRA = yes
MulticastDNS = yes

$addresses
$(printf '%s\n' "${route_sections[@]}")
EOF
)
        echo -e "$unit" > "$directory/00-$ifname.network"
    done
}

# main function
main() {
    if [[ $# -lt 4 ]]; then
        echo "USAGE: $0 addresses routes-v4 routes-v6 networkd-directory" >&2
        # exit 1
        return 1
    fi

    local addresses
    readarray -t addresses < <(jq -c '.[]' "$1") # Read JSON data into array

    local v4_routes
    readarray -t v4_routes < <(jq -c '.[]' "$2")

    local v6_routes
    readarray -t v6_routes < <(jq -c '.[]' "$3")

    local networkd_directory="$4"

    local relevant_interfaces
    readarray -t relevant_interfaces < <(filter_interfaces "${addresses[@]}")

    local relevant_routes
    readarray -t relevant_routes < <(filter_routes "${v4_routes[@]}" "${v6_routes[@]}")

    generate_networkd_units relevant_interfaces relevant_routes "$networkd_directory"
}

main "$@"
