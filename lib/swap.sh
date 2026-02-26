#!/usr/bin/env bash
# =============================================================================
# Swap File Module
# =============================================================================
# Ensures a swap file exists. Many cloud VMs ship with zero swap, which means
# zswap has nowhere to overflow and the memory defense model breaks.
#
# Swap size formula (same as Ubuntu installer):
#   RAM ≤ 2GB  → swap = RAM × 2
#   RAM ≤ 8GB  → swap = RAM
#   RAM > 8GB  → swap = max(4GB, RAM/2), capped at 8GB
# =============================================================================

setup_swap() {
    log_section "Swap File"

    # Check if swap already exists
    local current_swap_mb
    current_swap_mb=$(awk '/SwapTotal/ {print int($2/1024)}' /proc/meminfo)

    if [[ $current_swap_mb -gt 0 ]]; then
        log_ok "Swap already configured: ${current_swap_mb}MB"
        return
    fi

    # No swap — create one
    log_warn "No swap detected — creating swap file"

    # Calculate size
    local swap_gb
    if [[ $RAM_GB -le 2 ]]; then
        swap_gb=$(( RAM_GB * 2 ))
    elif [[ $RAM_GB -le 8 ]]; then
        swap_gb=$RAM_GB
    else
        swap_gb=$(( RAM_GB / 2 ))
        if [[ $swap_gb -lt 4 ]]; then swap_gb=4; fi
        if [[ $swap_gb -gt 8 ]]; then swap_gb=8; fi
    fi

    # Minimum 1GB
    if [[ $swap_gb -lt 1 ]]; then swap_gb=1; fi

    local swap_file="/swapfile"

    # Don't clobber an existing file
    if [[ -f "$swap_file" ]]; then
        log_warn "${swap_file} exists but is not active — activating"
        chmod 600 "$swap_file"
        mkswap "$swap_file" > /dev/null 2>&1 || true
        swapon "$swap_file" 2>/dev/null || true
        if [[ $(awk '/SwapTotal/ {print int($2/1024)}' /proc/meminfo) -gt 0 ]]; then
            log_ok "Activated existing ${swap_file}"
        else
            log_fail "Could not activate ${swap_file}"
        fi
        return
    fi

    # Create swap file
    log_ok "Creating ${swap_gb}GB swap file at ${swap_file}"
    dd if=/dev/zero of="$swap_file" bs=1M count=$(( swap_gb * 1024 )) status=progress 2>/dev/null
    chmod 600 "$swap_file"
    mkswap "$swap_file" > /dev/null 2>&1
    swapon "$swap_file"
    log_ok "Swap activated: ${swap_gb}GB"

    # Persist in fstab
    if ! grep -q "$swap_file" /etc/fstab; then
        echo "${swap_file} none swap sw 0 0" >> /etc/fstab
        log_ok "Added swap to fstab (persistent)"
    fi
}
