#!/usr/bin/env bash
# =============================================================================
# Security Module
# =============================================================================
# SSH hardening, firewall (ufw), service cleanup, and fail2ban.
# All changes are non-destructive and preserve existing access.
# =============================================================================

setup_ssh_hardening() {
    log_section "SSH Hardening"

    local SSH_CONF="/etc/ssh/sshd_config.d/agent-machine.conf"
    mkdir -p /etc/ssh/sshd_config.d/

    # Check if key-based auth is possible before disabling passwords
    local has_authorized_keys=false
    if [[ -n "$TARGET_USER" && "$TARGET_USER" != "nobody" ]]; then
        local user_home
        user_home=$(getent passwd "$TARGET_USER" | cut -d: -f6)
        if [[ -n "$user_home" && -s "${user_home}/.ssh/authorized_keys" ]]; then
            has_authorized_keys=true
        fi
    fi

    cat > "$SSH_CONF" << 'EOF'
# Agent Machine SSH Hardening
# https://github.com/craigvandotcom/agent-machine

# Authentication
MaxAuthTries 3
LoginGraceTime 30
PermitRootLogin no
PubkeyAuthentication yes

# Disable weak auth methods
KbdInteractiveAuthentication no
PermitEmptyPasswords no
X11Forwarding no

# Session limits
MaxSessions 10
MaxStartups 3:50:10
ClientAliveInterval 300
ClientAliveCountMax 3
EOF

    if [[ "$has_authorized_keys" == true ]]; then
        echo "PasswordAuthentication no" >> "$SSH_CONF"
        log_ok "SSH: key-only auth (authorized_keys found for ${TARGET_USER})"
    else
        echo "PasswordAuthentication yes" >> "$SSH_CONF"
        log_warn "SSH: password auth kept enabled (no authorized_keys found)"
        log_warn "  → Add your SSH key, then run: sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' ${SSH_CONF}"
    fi

    # Validate config before restarting
    if sshd -t 2>/dev/null; then
        systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
        log_ok "SSH config validated and reloaded"
    else
        rm -f "$SSH_CONF"
        log_fail "SSH config validation failed — removed our config, no changes applied"
    fi
}

setup_firewall() {
    log_section "Firewall (ufw)"

    if ! command -v ufw &>/dev/null; then
        apt-get install -y -qq ufw > /dev/null 2>&1
        log_ok "Installed ufw"
    fi

    # Check if already active
    if ufw status | grep -q "Status: active"; then
        log_ok "ufw already active"
        ufw status numbered 2>/dev/null | head -20
        return
    fi

    # Default policies
    ufw default deny incoming > /dev/null 2>&1
    ufw default allow outgoing > /dev/null 2>&1

    # SSH (always allow — never lock yourself out)
    ufw allow ssh > /dev/null 2>&1
    log_ok "Allowed SSH (port 22)"

    # HTTP/HTTPS (common for webhooks, APIs)
    ufw allow 80/tcp > /dev/null 2>&1
    ufw allow 443/tcp > /dev/null 2>&1
    log_ok "Allowed HTTP/HTTPS (80, 443)"

    # Enable (non-interactive)
    echo "y" | ufw enable > /dev/null 2>&1
    log_ok "ufw enabled: deny incoming, allow outgoing, SSH/HTTP/HTTPS allowed"
}

setup_fail2ban() {
    log_section "fail2ban (Brute Force Protection)"

    if ! command -v fail2ban-client &>/dev/null; then
        apt-get install -y -qq fail2ban > /dev/null 2>&1
        log_ok "Installed fail2ban"
    else
        log_ok "fail2ban already installed"
    fi

    # Custom jail config (don't modify main config — use .local override)
    cat > /etc/fail2ban/jail.local << 'EOF'
# Agent Machine — fail2ban config
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
mode    = aggressive
EOF

    systemctl enable --now fail2ban > /dev/null 2>&1
    systemctl restart fail2ban > /dev/null 2>&1
    log_ok "fail2ban enabled (SSH: 5 attempts → 1h ban)"
}

setup_disable_services() {
    log_section "Disable Unnecessary Services"

    local services_to_disable=(
        snapd.service
        snapd.socket
        cups.service
        cups-browsed.service
        avahi-daemon.service
        ModemManager.service
        bluetooth.service
        multipathd.service
    )

    local disabled_count=0
    for svc in "${services_to_disable[@]}"; do
        if systemctl is-enabled "$svc" &>/dev/null 2>&1; then
            systemctl disable --now "$svc" > /dev/null 2>&1 || true
            log_ok "Disabled: ${svc}"
            disabled_count=$((disabled_count + 1))
        fi
    done

    if [[ $disabled_count -eq 0 ]]; then
        log_ok "No unnecessary services found to disable"
    fi

    # Special handling: docker/containerd — only disable if user didn't explicitly install
    for svc in docker.service containerd.service; do
        if systemctl is-enabled "$svc" &>/dev/null 2>&1; then
            log_warn "${svc} is running — not disabling (may be intentional). Disable manually if unused:"
            log_warn "  sudo systemctl disable --now ${svc}"
        fi
    done
}

setup_auto_updates() {
    log_section "Automatic Security Updates"

    if dpkg -l unattended-upgrades &>/dev/null 2>&1; then
        log_ok "unattended-upgrades already installed"
    else
        apt-get install -y -qq unattended-upgrades > /dev/null 2>&1
        log_ok "Installed unattended-upgrades"
    fi

    # Enable automatic security updates only (not all updates)
    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

    cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

    systemctl enable --now unattended-upgrades > /dev/null 2>&1
    log_ok "Auto security updates enabled (no auto-reboot)"
}
