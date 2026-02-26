#!/usr/bin/env bash
# =============================================================================
# Verification Module
# =============================================================================
# Checks all tuning is applied correctly. Used by --check and post-install.
# =============================================================================

verify_performance() {
    log_section "Performance Verification"
    local issues=0

    # zswap
    local zswap_enabled
    zswap_enabled=$(cat /sys/module/zswap/parameters/enabled 2>/dev/null)
    if [[ "$zswap_enabled" == "Y" ]]; then
        log_ok "zswap: enabled ($(cat /sys/module/zswap/parameters/compressor), pool=$(cat /sys/module/zswap/parameters/max_pool_percent)%)"
    else
        log_fail "zswap: not enabled"; issues=$((issues + 1))
    fi

    # MGLRU
    local mglru
    mglru=$(cat /sys/kernel/mm/lru_gen/enabled 2>/dev/null || echo "0")
    if [[ "$mglru" != "0" && "$mglru" != "0x0000" ]]; then
        log_ok "MGLRU: active (${mglru})"
    else
        log_warn "MGLRU: not active (kernel may not support it)"
    fi

    # BBR
    local bbr
    bbr=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    if [[ "$bbr" == "bbr" ]]; then
        log_ok "TCP: BBR congestion control"
    else
        log_warn "TCP: ${bbr} (BBR not available)"; issues=$((issues + 1))
    fi

    # systemd-oomd
    if systemctl is-active systemd-oomd &>/dev/null; then
        log_ok "systemd-oomd: running"
    else
        log_fail "systemd-oomd: not running"; issues=$((issues + 1))
    fi

    # THP
    local thp
    thp=$(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null | grep -oP '\[\K[^\]]+')
    if [[ "$thp" == "madvise" ]]; then
        log_ok "THP: madvise (app opt-in)"
    else
        log_warn "THP: ${thp} (should be madvise)"
    fi

    # Key sysctl values
    log_ok "vfs_cache_pressure: $(sysctl -n vm.vfs_cache_pressure 2>/dev/null)"
    log_ok "watermark_scale_factor: $(sysctl -n vm.watermark_scale_factor 2>/dev/null)"
    log_ok "inotify.max_user_watches: $(sysctl -n fs.inotify.max_user_watches 2>/dev/null)"

    # noatime
    if mount | grep ' / ' | grep -q noatime; then
        log_ok "Filesystem: noatime active"
    else
        log_warn "Filesystem: noatime not active (may apply on reboot)"
    fi

    # SSH protection
    local ssh_oom
    ssh_oom=$(systemctl show ssh.service --property=ManagedOOMPreference 2>/dev/null | cut -d= -f2)
    if [[ "$ssh_oom" == "omit" ]]; then
        log_ok "SSH: protected from oomd"
    else
        log_warn "SSH: not protected from oomd"
    fi

    # PSI
    if [[ -f /proc/pressure/memory ]]; then
        local psi_some
        psi_some=$(awk '{print $2}' /proc/pressure/memory | head -1 | cut -d= -f2)
        log_ok "PSI: available (memory pressure avg10=${psi_some})"
    else
        log_warn "PSI: not available"
    fi

    echo ""
    PERF_ISSUES=$issues
}

verify_security() {
    log_section "Security Verification"
    local issues=0

    # SSH config
    if [[ -f /etc/ssh/sshd_config.d/agent-machine.conf ]]; then
        log_ok "SSH: hardening config present"
        if grep -q "PasswordAuthentication no" /etc/ssh/sshd_config.d/agent-machine.conf 2>/dev/null; then
            log_ok "SSH: password auth disabled"
        else
            log_warn "SSH: password auth still enabled"
        fi
        if grep -q "PermitRootLogin no" /etc/ssh/sshd_config.d/agent-machine.conf 2>/dev/null; then
            log_ok "SSH: root login disabled"
        fi
    else
        log_warn "SSH: no hardening config"; issues=$((issues + 1))
    fi

    # Firewall
    if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
        log_ok "Firewall: ufw active"
    else
        log_warn "Firewall: ufw not active"; issues=$((issues + 1))
    fi

    # fail2ban
    if systemctl is-active fail2ban &>/dev/null; then
        local banned
        banned=$(fail2ban-client status sshd 2>/dev/null | grep "Currently banned" | awk '{print $NF}')
        log_ok "fail2ban: running (${banned:-0} currently banned)"
    else
        log_warn "fail2ban: not running"; issues=$((issues + 1))
    fi

    # Auto updates
    if dpkg -l unattended-upgrades &>/dev/null 2>&1; then
        log_ok "Auto security updates: configured"
    else
        log_warn "Auto security updates: not configured"; issues=$((issues + 1))
    fi

    # Sysctl security
    local kptr
    kptr=$(sysctl -n kernel.kptr_restrict 2>/dev/null)
    if [[ "$kptr" == "2" ]]; then
        log_ok "Kernel: pointer addresses hidden"
    else
        log_warn "Kernel: kptr_restrict=${kptr} (should be 2)"
    fi

    echo ""
    SEC_ISSUES=$issues
}

verify_all() {
    PERF_ISSUES=0
    SEC_ISSUES=0

    verify_performance
    verify_security

    local total=$((PERF_ISSUES + SEC_ISSUES))
    if [[ $total -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}All checks passed.${NC}"
    else
        echo -e "${YELLOW}${BOLD}${total} issue(s) found — review warnings above.${NC}"
    fi
}
