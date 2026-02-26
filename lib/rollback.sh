#!/usr/bin/env bash
# =============================================================================
# Rollback Module
# =============================================================================
# Save state before changes, restore on --rollback.
# =============================================================================

ROLLBACK_DIR="/var/lib/agent-machine-rollback"

save_rollback() {
    log_section "Saving Rollback State"

    mkdir -p "$ROLLBACK_DIR"

    # Save current sysctl values
    sysctl -a 2>/dev/null > "${ROLLBACK_DIR}/sysctl-before.conf"
    log_ok "Saved sysctl state"

    # Save current GRUB config
    if [[ -f /etc/default/grub ]]; then
        cp /etc/default/grub "${ROLLBACK_DIR}/grub-before"
        log_ok "Saved GRUB config"
    fi

    # Save current fstab
    cp /etc/fstab "${ROLLBACK_DIR}/fstab-before"
    log_ok "Saved fstab"

    # Save current systemd overrides
    for dir in ssh.service.d "-.slice.d" "user@.service.d" "user-${TARGET_UID}.slice.d"; do
        if [[ -d "/etc/systemd/system/${dir}" ]]; then
            cp -r "/etc/systemd/system/${dir}" "${ROLLBACK_DIR}/" 2>/dev/null || true
        fi
    done
    log_ok "Saved systemd overrides"

    # Save SSH config
    if [[ -d /etc/ssh/sshd_config.d ]]; then
        cp -r /etc/ssh/sshd_config.d "${ROLLBACK_DIR}/" 2>/dev/null || true
        log_ok "Saved SSH config"
    fi

    # Record timestamp and version
    date -Iseconds > "${ROLLBACK_DIR}/timestamp"
    echo "1.0.0" > "${ROLLBACK_DIR}/version"
    log_ok "Rollback saved to ${ROLLBACK_DIR}"
}

do_rollback() {
    log_section "Rolling Back"

    if [[ ! -d "$ROLLBACK_DIR" ]]; then
        echo -e "${RED}No rollback state found at ${ROLLBACK_DIR}${NC}"
        echo "Agent Machine may not have been installed, or rollback was already performed."
        exit 1
    fi

    echo -e "Rolling back to state from $(cat "${ROLLBACK_DIR}/timestamp" 2>/dev/null || echo 'unknown')"

    # Remove our sysctl file
    rm -f /etc/sysctl.d/99-agent-machine.conf
    sysctl --system > /dev/null 2>&1
    log_ok "Removed sysctl tuning"

    # Restore GRUB
    if [[ -f "${ROLLBACK_DIR}/grub-before" ]]; then
        cp "${ROLLBACK_DIR}/grub-before" /etc/default/grub
        update-grub 2>/dev/null || true
        log_ok "Restored GRUB config"
    fi

    # Restore fstab
    if [[ -f "${ROLLBACK_DIR}/fstab-before" ]]; then
        cp "${ROLLBACK_DIR}/fstab-before" /etc/fstab
        log_ok "Restored fstab"
    fi

    # Remove our systemd overrides
    rm -f /etc/systemd/system/ssh.service.d/agent-machine.conf
    rm -f /etc/systemd/system/-.slice.d/oomd.conf
    rm -f /etc/systemd/system/user@.service.d/oomd.conf
    rm -f /etc/systemd/oomd.conf
    rm -f /etc/tmpfiles.d/agent-machine-thp.conf
    rm -f /etc/udev/rules.d/60-agent-machine-io.rules
    for f in /etc/systemd/system/user-*.slice.d/agent-machine.conf; do
        rm -f "$f" 2>/dev/null
    done
    systemctl daemon-reload
    log_ok "Removed systemd overrides"

    # Remove SSH hardening (but don't touch existing config)
    rm -f /etc/ssh/sshd_config.d/agent-machine.conf
    sshd -t 2>/dev/null && systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
    log_ok "Removed SSH hardening config"

    # Disable oomd if we installed it
    systemctl disable --now systemd-oomd 2>/dev/null || true
    log_ok "Disabled systemd-oomd"

    # Note: we don't remove ufw, fail2ban, or unattended-upgrades
    # — they're security packages that only help, and removing them could expose the server

    echo ""
    echo -e "${GREEN}Rollback complete. Reboot recommended for full effect.${NC}"
    echo -e "Rollback state preserved at ${ROLLBACK_DIR} — delete manually if no longer needed."
}
