#!/bin/bash

set -euo pipefail

# Keep track of deleted uids and gids
UID_MAP_FILE="/var/lib/nixos/uid-map"
GID_MAP_FILE="/var/lib/nixos/gid-map"
UID_MAP=$(jq -r 'to_entries|map("\(.key)=\(.value)")|.[]' < "$UID_MAP_FILE")
GID_MAP=$(jq -r 'to_entries|map("\(.key)=\(.value)")|.[]' < "$GID_MAP_FILE")

DRY_RUN="${NIXOS_ACTION:-dry-activate}"

mkdir -p "/var/lib/nixos"

update_file() {
    local path="$1"
    local contents="$2"
    local perms="${3:-0644}"
    if [[ "$DRY_RUN" != "dry-activate" ]]; then
        echo "$contents" > "$path"
        chmod "$perms" "$path"
    else
        echo "Would update $path with permissions $perms"
    fi
}

nscd_invalidate() {
    if [[ "$DRY_RUN" != "dry-activate" ]]; then
        nscd --invalidate "$1"
    else
        echo "Would invalidate nscd $1"
    fi
}

hash_password() {
    local password="$1"
    local salt=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 8)
    echo "$6$${salt}\$$(echo -n "$password" | openssl passwd -1 -salt "$salt" -stdin)"
}

allocate_gid() {
    local name="$1"
    local prev_gid="${GID_MAP[$name]}"
    if [[ -n "$prev_gid" && -z "${GIDS_USED[$prev_gid]+x}" ]]; then
        echo "Would revive group '$name' with GID $prev_gid"
        GIDS_USED[$prev_gid]=1
        echo "$prev_gid"
    else
        for gid in {400..999}; do
            if [[ -z "${GIDS_USED[$gid]+x}" && -z "${GIDS_PREV_USED[$gid]+x}" ]]; then
                GIDS_USED[$gid]=1
                echo "$gid"
                return
            fi
        done
        echo "Out of free GIDs" >&2
        exit 1
    fi
}

allocate_uid() {
    local name="$1"
    local is_system_user="$2"
    local min max up
    if [[ "$is_system_user" == "true" ]]; then
        min=400 max=999 up=0
    else
        min=1000 max=29999 up=1
    fi
    local prev_uid="${UID_MAP[$name]}"
    if [[ -n "$prev_uid" && "$prev_uid" -ge "$min" && "$prev_uid" -le "$max" && -z "${UIDS_USED[$prev_uid]+x}" ]]; then
        echo "Would revive user '$name' with UID $prev_uid"
        UIDS_USED[$prev_uid]=1
        echo "$prev_uid"
    else
        for uid in $(seq "$min" "$up" "$max"); do
            if [[ -z "${UIDS_USED[$uid]+x}" && -z "${UIDS_PREV_USED[$uid]+x}" ]]; then
                UIDS_USED[$uid]=1
                echo "$uid"
                return
            fi
        done
        echo "Out of free UIDs" >&2
        exit 1
    fi
}

spec=$(jq -r 'tojson' < "$1")

# Don't allocate UIDs/GIDs that are manually assigned
for g in $(echo "$spec" | jq -r '.groups[].gid'); do
    GIDS_USED[$g]=1
done
for u in $(echo "$spec" | jq -r '.users[].uid'); do
    UIDS_USED[$u]=1
done

# Likewise for previously used but deleted UIDs/GIDs
for uid in ${UID_MAP[@]}; do
    UIDS_PREV_USED[${uid%%=*}]=1
done
for gid in ${GID_MAP[@]}; do
    GIDS_PREV_USED[${gid%%=*}]=1
done

# Generate a new /etc/group containing the declared groups
declare -A groups_out
for g in $(echo "$spec" | jq -r '.groups[]'); do
    name=$(echo "$g" | jq -r '.name')
    gid=$(allocate_gid "$name")
    members=$(echo "$g" | jq -r '.members[]' | paste -sd,)
    groups_out[$name]="$name:x:$gid:$members"
done

# Rewrite /etc/group
update_file "/etc/group" "$(printf '%s\n' "${groups_out[@]}")"
nscd_invalidate "group"

# Generate a new /etc/passwd containing the declared users
declare -A users_out
for u in $(echo "$spec" | jq -r '.users[]'); do
    name=$(echo "$u" | jq -r '.name')
    uid=$(allocate_uid "$name" "$(echo "$u" | jq -r '.isSystemUser')")
    gid=$(echo "$u" | jq -r '.gid')
    if [[ "$gid" =~ ^[0-9]+$ ]]; then
        :
    elif [[ -n "${groups_out[$gid]+x}" ]]; then
        gid="${groups_out[$gid]%%:*}"
    else
        echo "warning: user '$name' has unknown group '$gid'" >&2
        gid=65534
    fi
    home=$(echo "$u" | jq -r '.home')
    shell=$(echo "$u" | jq -r '.shell')
    users_out[$name]="$name:x:$uid:$gid::/home/$name:/bin/bash"
done

# Rewrite /etc/passwd
update_file "/etc/passwd" "$(printf '%s\n' "${users_out[@]}")"
nscd_invalidate "passwd"

# Rewrite /etc/shadow to add new accounts or remove dead ones
declare -A shadow_seen
shadow_new=()
while IFS=':' read -ra fields; do
    name="${fields[0]}"
    password="${fields[1]}"
    if [[ -n "${users_out[$name]+x}" ]]; then
        if [[ "$DRY_RUN" == "dry-activate" ]]; then
            password="${users_out[$name]}"
        fi
        shadow_new+=("$name:$password:1::::::") 
        shadow_seen[$name]=1
    else
        shadow_new+=("$name:!:1::::::") 
    fi
done < /etc/shadow

for u in "${!users_out[@]}"; do
    if [[ -z "${shadow_seen[$u]+x}" ]]; then
        shadow_new+=("$u:$(hash_password ""):1::::::") 
    fi
done

update_file "/etc/shadow" "$(printf '%s\n' "${shadow_new[@]}")" 0640
chown root:shadow /etc/shadow

# Rewrite /etc/subuid & /etc/subgid to include default container mappings
sub_uid_map_file="/var/lib/nixos/auto-subuid-map"
sub_uid_map=$(jq -r 'to_entries|map("\(.key)=\(.value)")|.[]' < "$sub_uid_map_file")

declare -A sub_uids_used sub_uids_prev_used
for uid in ${sub_uid_map[@]}; do
    sub_uids_prev_used[${uid%%=*}]=1
done

allocate_sub_uid() {
    local name="$1"
    local min=100000 max=$((100000 * 100)) up=1
    local prev_id="${sub_uid_map[$name]}"
    if [[ -n "$prev_id" && -z "${sub_uids_used[$prev_id]+x}" ]]; then
        sub_uids_used[$prev_id]=1
        echo "$prev_id"
    else
        for uid in $(seq "$min" "$up" "$max"); do
            if [[ -z "${sub_uids_used[$uid]+x}" && -z "${sub_uids_prev_used[$uid]+x}" ]]; then
                sub_uids_used[$uid]=1
                local offset=$((uid - 100000))
                local count=$((offset * 65536))
                local subordinate=$((100000 + count))
                echo "$subordinate"
                return
            fi
        done
        echo "Out of free sub UIDs" >&2
        exit 1
    fi
}

sub_uids=()
sub_gids=()
for u in "${!users_out[@]}"; do
    for range in $(echo "${users_out[$u]}" | jq -r '.subUidRanges[]'); do
        start=$(echo "$range" | jq -r '.startUid')
        count=$(echo "$range" | jq -r '.count')
        sub_uids+=("$u:$start:$count")
    done
    for range in $(echo "${users_out[$u]}" | jq -r '.subGidRanges[]'); do
        start=$(echo "$range" | jq -r '.startGid')
        count=$(echo "$range" | jq -r '.count')
        sub_gids+=("$u:$start:$count")
    done
done

update_file "/etc/subuid" "$(printf '%s\n' "${sub_uids[@]}")"
update_file "/etc/subgid" "$(printf '%s\n' "${sub_gids[@]}")"
