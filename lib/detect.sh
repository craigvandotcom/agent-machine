#!/usr/bin/env bash
# =============================================================================
# Hardware Detection Module
# =============================================================================
# Detects RAM, CPUs, disk type, kernel version, virtualization, and calculates
# scaled parameters for all other modules.
# =============================================================================

detect_hardware() {
    log_section "Detecting Hardware"

    # RAM (in MB)
    RAM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
    RAM_GB=$(( RAM_MB / 1024 ))
    log_ok "RAM: ${RAM_GB}GB (${RAM_MB}MB)"

    # CPUs
    CPU_COUNT=$(nproc)
    log_ok "CPUs: ${CPU_COUNT}"

    # Kernel
    KERNEL_VERSION=$(uname -r)
    KERNEL_MAJOR=$(echo "$KERNEL_VERSION" | cut -d. -f1)
    KERNEL_MINOR=$(echo "$KERNEL_VERSION" | cut -d. -f2)
    log_ok "Kernel: ${KERNEL_VERSION}"

    # Disk type and device (handles /dev/sda1, /dev/vda1, /dev/nvme0n1p1, /dev/mapper/*)
    local raw_source
    raw_source=$(findmnt -n -o SOURCE /)
    # Resolve to physical device via lsblk (handles LVM, dm-*, partitions)
    ROOT_DEV_SHORT=$(lsblk -ndo PKNAME "$raw_source" 2>/dev/null || basename "$raw_source" | sed 's/[0-9]*$//')
    # Fallback: if lsblk didn't return anything useful
    if [[ -z "$ROOT_DEV_SHORT" || "$ROOT_DEV_SHORT" == "null" ]]; then
        ROOT_DEV_SHORT=$(basename "$raw_source" | sed 's/[0-9]*$//' | sed 's/p$//')
    fi
    ROOT_DEV="/dev/${ROOT_DEV_SHORT}"
    if [[ -f "/sys/block/${ROOT_DEV_SHORT}/queue/rotational" ]]; then
        IS_SSD=$(( 1 - $(cat "/sys/block/${ROOT_DEV_SHORT}/queue/rotational") ))
    else
        IS_SSD=1  # assume SSD on VPS
    fi
    DISK_SCHEDULER=$(cat "/sys/block/${ROOT_DEV_SHORT}/queue/scheduler" 2>/dev/null || echo "unknown")
    if [[ $IS_SSD -eq 1 ]]; then
        log_ok "Disk: SSD (${ROOT_DEV}) scheduler: ${DISK_SCHEDULER}"
    else
        log_ok "Disk: HDD (${ROOT_DEV}) scheduler: ${DISK_SCHEDULER}"
    fi

    # Virtualization
    VIRT_TYPE=$(systemd-detect-virt 2>/dev/null || echo "none")
    log_ok "Virtualization: ${VIRT_TYPE}"

    # Distro
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO_ID="${ID:-unknown}"
        DISTRO_VERSION="${VERSION_ID:-unknown}"
        log_ok "Distro: ${PRETTY_NAME:-${DISTRO_ID} ${DISTRO_VERSION}}"
    else
        DISTRO_ID="unknown"
        DISTRO_VERSION="unknown"
        log_warn "Could not detect distro"
    fi

    # Calculate scaled parameters based on RAM
    # min_free_kbytes: ~0.8% of RAM, capped at 256MB
    MIN_FREE_KB=$(( RAM_MB * 1024 * 8 / 1000 ))
    if [[ $MIN_FREE_KB -gt 262144 ]]; then MIN_FREE_KB=262144; fi
    if [[ $MIN_FREE_KB -lt 65536 ]]; then MIN_FREE_KB=65536; fi

    # zswap max pool: 20% of RAM
    ZSWAP_POOL_PCT=20

    # dirty ratios: scale for SSD vs HDD
    if [[ $IS_SSD -eq 1 ]]; then
        DIRTY_BG_RATIO=3
        DIRTY_RATIO=10
    else
        DIRTY_BG_RATIO=10
        DIRTY_RATIO=20
    fi

    # Memory limits for user slice (reserve headroom for OS)
    if [[ $RAM_GB -le 4 ]]; then
        USER_MEM_HIGH=$(( RAM_GB * 3 / 4 ))G   # 75% of RAM
        USER_MEM_MAX=$(( RAM_GB * 7 / 8 ))G    # 87.5% of RAM
    elif [[ $RAM_GB -le 8 ]]; then
        USER_MEM_HIGH=$(( RAM_GB - 2 ))G
        USER_MEM_MAX=$(( RAM_GB - 1 ))G
    elif [[ $RAM_GB -le 32 ]]; then
        USER_MEM_HIGH=$(( RAM_GB - 4 ))G
        USER_MEM_MAX=$(( RAM_GB - 2 ))G
    else
        USER_MEM_HIGH=$(( RAM_GB - 6 ))G
        USER_MEM_MAX=$(( RAM_GB - 3 ))G
    fi

    log_ok "Calculated: min_free=${MIN_FREE_KB}KB, dirty_bg=${DIRTY_BG_RATIO}%, dirty=${DIRTY_RATIO}%"
    log_ok "Calculated: user_mem_high=${USER_MEM_HIGH}, user_mem_max=${USER_MEM_MAX}"
}

# Detect the primary non-root user (for cgroup/security setup)
detect_user() {
    if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
        TARGET_USER="$SUDO_USER"
    else
        # Find first user with UID >= 1000
        TARGET_USER=$(awk -F: '$3 >= 1000 && $3 < 65534 && $7 ~ /bash|zsh/ {print $1; exit}' /etc/passwd)
    fi

    if [[ -z "$TARGET_USER" ]]; then
        log_warn "Could not detect non-root user — cgroup/security settings may need manual adjustment"
        TARGET_USER="nobody"
        TARGET_UID=65534
    else
        TARGET_UID=$(id -u "$TARGET_USER")
        log_ok "Target user: ${TARGET_USER} (UID ${TARGET_UID})"
    fi
}
