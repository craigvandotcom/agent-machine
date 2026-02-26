#!/usr/bin/env bash
# =============================================================================
# Monitoring Module
# =============================================================================
# Installs observation tools and a PSI (Pressure Stall Information) monitor.
# =============================================================================

setup_monitoring() {
    log_section "Monitoring Tools"

    local packages_to_install=()

    command -v btop &>/dev/null || packages_to_install+=(btop)
    command -v atop &>/dev/null || packages_to_install+=(atop)
    command -v iotop-c &>/dev/null || dpkg -l iotop-c &>/dev/null 2>&1 || packages_to_install+=(iotop-c)
    dpkg -l bpfcc-tools &>/dev/null 2>&1 || packages_to_install+=(bpfcc-tools)
    dpkg -l linux-headers-"$(uname -r)" &>/dev/null 2>&1 || packages_to_install+=(linux-headers-"$(uname -r)")

    if [[ ${#packages_to_install[@]} -gt 0 ]]; then
        apt-get update -qq > /dev/null 2>&1
        apt-get install -y -qq "${packages_to_install[@]}" > /dev/null 2>&1 || log_warn "Some packages failed to install"
        log_ok "Installed: ${packages_to_install[*]}"
    else
        log_ok "All monitoring tools already installed"
    fi

    # Enable atop logging daemon
    if systemctl is-enabled atop &>/dev/null 2>&1; then
        log_ok "atop logging already enabled"
    else
        systemctl enable --now atop 2>/dev/null || true
        log_ok "atop logging enabled"
    fi

    # Install PSI monitoring script
    cat > /usr/local/bin/psi-watch << 'SCRIPT'
#!/usr/bin/env bash
# Real-time PSI (Pressure Stall Information) monitor
# Shows actual work lost due to resource shortage
while true; do
    clear
    echo "=== PSI Monitor — $(date '+%H:%M:%S') ==="
    echo ""
    echo "--- CPU ---"
    cat /proc/pressure/cpu
    echo ""
    echo "--- Memory ---"
    cat /proc/pressure/memory
    echo ""
    echo "--- I/O ---"
    cat /proc/pressure/io
    echo ""
    echo "--- zswap ---"
    if [[ -d /sys/kernel/debug/zswap ]]; then
        stored=$(cat /sys/kernel/debug/zswap/stored_pages 2>/dev/null || echo "?")
        pool=$(cat /sys/kernel/debug/zswap/pool_total_size 2>/dev/null || echo "?")
        writeback=$(cat /sys/kernel/debug/zswap/written_back_pages 2>/dev/null || echo "?")
        echo "  stored_pages: ${stored}  pool_size: ${pool}  written_back: ${writeback}"
    else
        echo "  (run as root for zswap stats)"
    fi
    sleep 2
done
SCRIPT
    chmod +x /usr/local/bin/psi-watch
    log_ok "Installed psi-watch command"
}
