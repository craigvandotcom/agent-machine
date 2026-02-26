#!/usr/bin/env bash
# =============================================================================
# Performance Module
# =============================================================================
# zswap, kernel sysctl, systemd-oomd, cgroup priorities, filesystem tuning.
#
# Three-layer memory defense (immune system model):
#   Layer 1: MemoryHigh → throttle (slow processes down)
#   Layer 2: systemd-oomd → surgical kill (remove worst offender)
#   Layer 3: kernel OOM → emergency kill (last resort, prevents freeze)
# =============================================================================

# --- Step 1: zswap (Compressed Swap in RAM) ---

setup_zswap() {
    log_section "zswap (Compressed Swap in RAM)"

    local current_enabled
    current_enabled=$(cat /sys/module/zswap/parameters/enabled 2>/dev/null || echo "N")

    if [[ "$current_enabled" == "Y" ]]; then
        local current_comp
        current_comp=$(cat /sys/module/zswap/parameters/compressor)
        log_ok "zswap already enabled (compressor: ${current_comp})"

        local current_pool current_zpool
        current_pool=$(cat /sys/module/zswap/parameters/max_pool_percent)
        current_zpool=$(cat /sys/module/zswap/parameters/zpool)
        if [[ "$current_comp" != "zstd" || "$current_zpool" != "zsmalloc" ]]; then
            log_warn "Suboptimal config detected — will fix on next reboot via GRUB"
        fi
    else
        echo zsmalloc > /sys/module/zswap/parameters/zpool
        echo zstd > /sys/module/zswap/parameters/compressor
        echo "$ZSWAP_POOL_PCT" > /sys/module/zswap/parameters/max_pool_percent
        echo Y > /sys/module/zswap/parameters/enabled
        log_ok "Enabled: compressor=zstd, zpool=zsmalloc, max_pool=${ZSWAP_POOL_PCT}%"
    fi

    # Persist via GRUB
    local GRUB_FILE="/etc/default/grub"
    local ZSWAP_PARAMS="zswap.enabled=1 zswap.compressor=zstd zswap.zpool=zsmalloc zswap.max_pool_percent=${ZSWAP_POOL_PCT}"
    if [[ ! -f "$GRUB_FILE" ]]; then
        log_skip "No GRUB config found (cloud-init or EFI stub boot?)"
    elif grep -q "zswap.enabled" "$GRUB_FILE" 2>/dev/null; then
        log_ok "GRUB already has zswap params"
    else
        sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\1 ${ZSWAP_PARAMS}\"/" "$GRUB_FILE"
        update-grub 2>/dev/null || true
        log_ok "Persisted zswap in GRUB"
    fi
}

# --- Step 2: Kernel sysctl Tuning ---

setup_sysctl() {
    log_section "Kernel Sysctl Tuning"

    local SYSCTL_FILE="/etc/sysctl.d/99-agent-machine.conf"

    cat > "$SYSCTL_FILE" << EOF
# =============================================================================
# Agent Machine — Performance + Security Tuning
# Generated: $(date -I) | Hardware: ${RAM_GB}GB RAM, ${CPU_COUNT} CPUs, $([ $IS_SSD -eq 1 ] && echo "SSD" || echo "HDD")
# https://github.com/craigvandotcom/agent-machine
# =============================================================================

# --- Memory Management ---
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_background_ratio = ${DIRTY_BG_RATIO}
vm.dirty_ratio = ${DIRTY_RATIO}
vm.min_free_kbytes = ${MIN_FREE_KB}
vm.watermark_scale_factor = 125
vm.compaction_proactiveness = 0
vm.page-cluster = 1
vm.zone_reclaim_mode = 0

# --- Network: BBR Congestion Control ---
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# --- Network: Buffer Sizing ---
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.ipv4.tcp_rmem = 4096 131072 16777216
net.ipv4.tcp_wmem = 4096 87380 16777216

# --- Network: Connection Handling ---
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 4096
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_tw_reuse = 2

# --- Scheduler ---
kernel.sched_autogroup_enabled = 0

# --- Filesystem ---
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512

# --- Security (zero performance cost) ---
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.tcp_syncookies = 1
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
EOF

    # Load BBR module if needed
    modprobe tcp_bbr 2>/dev/null || true

    # Apply
    sysctl --system > /dev/null 2>&1
    log_ok "Applied sysctl ($(wc -l < "$SYSCTL_FILE") lines)"

    # Verify critical settings
    local bbr_check
    bbr_check=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    if [[ "$bbr_check" == "bbr" ]]; then
        log_ok "BBR congestion control active"
    else
        log_warn "BBR not available — keeping $(sysctl -n net.ipv4.tcp_congestion_control)"
    fi
}

# --- Step 3: systemd-oomd (Proactive OOM Defense) ---

setup_oomd() {
    log_section "systemd-oomd (Proactive OOM Defense)"

    if ! command -v oomctl &>/dev/null; then
        apt-get install -y -qq systemd-oomd > /dev/null 2>&1
        log_ok "Installed systemd-oomd"
    else
        log_ok "systemd-oomd already installed"
    fi

    cat > /etc/systemd/oomd.conf << 'EOF'
[OOM]
SwapUsedLimit=80%
DefaultMemoryPressureLimit=60%
DefaultMemoryPressureDurationSec=45s
EOF
    log_ok "Configured /etc/systemd/oomd.conf"

    # Root slice: swap-based killing
    mkdir -p /etc/systemd/system/-.slice.d/
    cat > /etc/systemd/system/-.slice.d/oomd.conf << 'EOF'
[Slice]
ManagedOOMSwap=kill
EOF
    log_ok "Root slice: ManagedOOMSwap=kill"

    # User sessions: memory pressure killing
    mkdir -p /etc/systemd/system/user@.service.d/
    cat > /etc/systemd/system/user@.service.d/oomd.conf << 'EOF'
[Service]
ManagedOOMMemoryPressure=kill
ManagedOOMMemoryPressureLimit=60%
EOF
    log_ok "User sessions: ManagedOOMMemoryPressure=kill"

    systemctl enable --now systemd-oomd > /dev/null 2>&1
    log_ok "systemd-oomd enabled and running"
}

# --- Step 4: cgroup Priorities ---

setup_cgroups() {
    log_section "cgroup Priorities"

    # SSH: Protected, high priority, never swapped to disk
    mkdir -p /etc/systemd/system/ssh.service.d/
    cat > /etc/systemd/system/ssh.service.d/agent-machine.conf << 'EOF'
[Service]
ManagedOOMPreference=omit
CPUWeight=300
IOWeight=1000
MemoryMin=32M
MemoryLow=64M
MemorySwapMax=0
EOF
    log_ok "SSH: protected (omit from oomd, CPU=300, IO=1000)"

    # User slice: Controlled workload zone
    local user_slice="user-${TARGET_UID}.slice"
    mkdir -p "/etc/systemd/system/${user_slice}.d/"

    cat > "/etc/systemd/system/${user_slice}.d/agent-machine.conf" << EOF
[Slice]
MemoryLow=2G
MemoryHigh=${USER_MEM_HIGH}
MemoryMax=${USER_MEM_MAX}
CPUWeight=75
IOWeight=50
EOF
    log_ok "User slice (${user_slice}): MemHigh=${USER_MEM_HIGH}, MemMax=${USER_MEM_MAX}"

    systemctl daemon-reload
    log_ok "systemd reloaded"
}

# --- Step 5: Filesystem Tuning ---

setup_filesystem() {
    log_section "Filesystem Tuning"

    # noatime + commit interval
    if grep -q "noatime" /etc/fstab; then
        log_ok "noatime already in fstab"
    else
        local fstab_patched=false
        if [[ $IS_SSD -eq 1 ]]; then
            cp /etc/fstab /etc/fstab.pre-agent-machine
            sed -i '/[[:space:]]\/[[:space:]]/ s/defaults/defaults,noatime,commit=30/' /etc/fstab
            if grep -q "noatime" /etc/fstab; then
                fstab_patched=true
            else
                sed -i '/[[:space:]]\/[[:space:]]/ s/errors=remount-ro/errors=remount-ro,noatime,commit=30/' /etc/fstab
                if grep -q "noatime" /etc/fstab; then
                    fstab_patched=true
                fi
            fi
            if [[ "$fstab_patched" == true ]]; then
                log_ok "Added noatime,commit=30 to fstab"
            else
                cp /etc/fstab.pre-agent-machine /etc/fstab
                log_warn "Could not auto-patch fstab — add 'noatime,commit=30' to root mount manually"
            fi
            rm -f /etc/fstab.pre-agent-machine
        fi
        mount -o remount,noatime / 2>/dev/null && log_ok "Mounted / with noatime" || log_warn "Could not remount / — will apply on reboot"
    fi

    # Transparent Huge Pages: madvise (app opt-in only)
    local thp_current
    thp_current=$(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null | grep -oP '\[\K[^\]]+')
    if [[ "$thp_current" == "madvise" ]]; then
        log_ok "THP already set to madvise"
    else
        echo madvise > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
        echo "defer+madvise" > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || true
        mkdir -p /etc/tmpfiles.d/
        cat > /etc/tmpfiles.d/agent-machine-thp.conf << 'EOF'
w /sys/kernel/mm/transparent_hugepage/enabled - - - - madvise
w /sys/kernel/mm/transparent_hugepage/defrag - - - - defer+madvise
EOF
        log_ok "THP set to madvise (persistent)"
    fi

    # I/O scheduler udev rules
    cat > /etc/udev/rules.d/60-agent-machine-io.rules << 'EOF'
# NVMe: no scheduler (device has internal queuing)
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="none"
# SATA SSD: mq-deadline for fairness
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
# HDD: bfq for fairness
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
EOF
    udevadm control --reload-rules 2>/dev/null || true
    log_ok "I/O scheduler rules installed"
}
