#!/usr/bin/env bash
# =============================================================================
# Agent Machine
# =============================================================================
#
# Transforms a stock Ubuntu VPS into a hardened, high-performance AI workstation.
# One command. Auto-detects hardware. Full rollback support.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/craigvandotcom/agent-machine/main/install.sh | sudo bash
#
#   # Or clone and run:
#   sudo bash install.sh              # Full install (performance + security)
#   sudo bash install.sh --perf-only  # Performance tuning only
#   sudo bash install.sh --sec-only   # Security hardening only
#   sudo bash install.sh --check      # Verify current state
#   sudo bash install.sh --rollback   # Revert all changes
#   sudo bash install.sh --dry-run    # Show what would change
#
# Supported: Ubuntu 22.04+, Debian 12+, kernel 5.15+
#
# What it does:
#   Performance:
#     0. Creates swap file if none exists (many cloud VMs ship with 0 swap)
#     1. Enables zswap (compressed swap in RAM, ~3x compression)
#     2. Tunes kernel via sysctl (memory, network BBR, I/O, scheduler)
#     3. Configures systemd-oomd (proactive OOM defense)
#     4. Sets cgroup priorities (SSH protected, AI sessions managed)
#     5. Optimizes filesystem (noatime, THP=madvise, I/O scheduler)
#     6. Installs monitoring tools (btop, atop, psi-watch)
#
#   Security:
#     7. Hardens SSH (key-only auth, no root, rate limiting)
#     8. Enables firewall (ufw: deny incoming, allow SSH/HTTP/HTTPS)
#     9. Installs fail2ban (brute force protection)
#    10. Disables unnecessary services (snapd, cups, avahi, etc.)
#    11. Enables automatic security updates
#
# Three-layer memory defense:
#   Layer 1: MemoryHigh → throttle (slow processes down)
#   Layer 2: systemd-oomd → surgical kill (remove worst offender)
#   Layer 3: kernel OOM → emergency kill (last resort, prevents freeze)
#
# =============================================================================

set -euo pipefail

VERSION="1.0.0"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Logging ---
log_section() { echo -e "\n${BOLD}${BLUE}=== $1 ===${NC}"; }
log_ok()      { echo -e "  ${GREEN}✓${NC} $1"; }
log_warn()    { echo -e "  ${YELLOW}!${NC} $1"; }
log_skip()    { echo -e "  ${CYAN}→${NC} $1 (skipped)"; }
log_fail()    { echo -e "  ${RED}✗${NC} $1"; }

# --- Preflight ---
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Run with sudo: sudo bash install.sh${NC}"
        exit 1
    fi
}

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        echo -e "${RED}Cannot detect OS. Only Ubuntu 22.04+ and Debian 12+ are supported.${NC}"
        exit 1
    fi
    . /etc/os-release
    case "$ID" in
        ubuntu)
            if [[ "${VERSION_ID%%.*}" -lt 22 ]]; then
                echo -e "${RED}Ubuntu ${VERSION_ID} is not supported. Minimum: 22.04${NC}"
                exit 1
            fi
            ;;
        debian)
            if [[ "${VERSION_ID%%.*}" -lt 12 ]]; then
                echo -e "${RED}Debian ${VERSION_ID} is not supported. Minimum: 12${NC}"
                exit 1
            fi
            ;;
        *)
            echo -e "${YELLOW}Warning: ${PRETTY_NAME} is not officially supported. Proceeding anyway...${NC}"
            ;;
    esac
}

# --- Resolve library path (works for both curl|bash and local execution) ---
resolve_lib_dir() {
    # If running from a local clone, use relative path
    # BASH_SOURCE[0] is empty or "bash"/"main" when piped via curl|bash
    local script_dir=""
    if [[ -n "${BASH_SOURCE[0]:-}" && "${BASH_SOURCE[0]}" != "bash" && "${BASH_SOURCE[0]}" != "main" ]]; then
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || true
    fi

    if [[ -n "$script_dir" && -d "${script_dir}/lib" ]]; then
        LIB_DIR="${script_dir}/lib"
        return
    fi

    # Running via curl|bash — download modules to temp dir
    LIB_DIR=$(mktemp -d)
    TEMP_LIB_DIR="$LIB_DIR"  # track for cleanup
    echo -e "  ${CYAN}→${NC} Downloading modules..."
    local base_url="https://raw.githubusercontent.com/craigvandotcom/agent-machine/main/lib"
    for module in detect.sh swap.sh performance.sh security.sh monitoring.sh verify.sh rollback.sh; do
        curl -fsSL "${base_url}/${module}" -o "${LIB_DIR}/${module}" || {
            echo -e "${RED}Failed to download ${module}. Check your internet connection.${NC}"
            exit 1
        }
    done
    echo -e "  ${GREEN}✓${NC} Modules downloaded"
}

cleanup_temp() {
    if [[ -n "${TEMP_LIB_DIR:-}" && -d "$TEMP_LIB_DIR" ]]; then
        rm -rf "$TEMP_LIB_DIR"
    fi
}
trap cleanup_temp EXIT

# --- Source modules ---
load_modules() {
    resolve_lib_dir
    for module in detect.sh swap.sh performance.sh security.sh monitoring.sh verify.sh rollback.sh; do
        source "${LIB_DIR}/${module}"
    done
}

# =============================================================================
# Commands
# =============================================================================

cmd_full() {
    check_root
    check_os
    load_modules

    echo -e "${BOLD}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║        Agent Machine v${VERSION}                      ║${NC}"
    echo -e "${BOLD}║        Performance + Security for AI VMs         ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"

    detect_hardware
    detect_user
    save_rollback

    # Refresh package cache once (avoids stale cache on fresh VMs)
    log_section "Updating Package Cache"
    apt-get update -qq > /dev/null 2>&1
    log_ok "Package cache updated"

    # Performance
    setup_swap
    setup_zswap
    setup_sysctl
    setup_oomd
    setup_cgroups
    setup_filesystem
    setup_monitoring

    # Security
    setup_ssh_hardening
    setup_firewall
    setup_fail2ban
    setup_disable_services
    setup_auto_updates

    # Verify
    verify_all

    echo ""
    log_section "Complete"
    echo -e "  ${GREEN}Verify:${NC}    sudo bash install.sh --check"
    echo -e "  ${GREEN}Rollback:${NC}  sudo bash install.sh --rollback"
    echo -e "  ${GREEN}Monitor:${NC}   psi-watch | btop | atop"
    echo -e "  ${GREEN}OOM logs:${NC}  journalctl -u systemd-oomd -f"
    echo -e "  ${GREEN}Banned:${NC}    sudo fail2ban-client status sshd"
    echo ""
    echo -e "  ${YELLOW}Note:${NC} Some settings (fstab, zswap GRUB) take full effect on reboot."
}

cmd_perf_only() {
    check_root
    check_os
    load_modules

    echo -e "${BOLD}Agent Machine v${VERSION} — Performance Only${NC}"

    detect_hardware
    detect_user
    save_rollback

    apt-get update -qq > /dev/null 2>&1

    setup_swap
    setup_zswap
    setup_sysctl
    setup_oomd
    setup_cgroups
    setup_filesystem
    setup_monitoring

    verify_performance
}

cmd_sec_only() {
    check_root
    check_os
    load_modules

    echo -e "${BOLD}Agent Machine v${VERSION} — Security Only${NC}"

    detect_hardware
    detect_user
    save_rollback

    apt-get update -qq > /dev/null 2>&1

    setup_ssh_hardening
    setup_firewall
    setup_fail2ban
    setup_disable_services
    setup_auto_updates

    verify_security
}

cmd_check() {
    check_root
    load_modules
    detect_hardware
    detect_user
    verify_all
}

cmd_rollback() {
    check_root
    load_modules
    detect_hardware
    detect_user
    do_rollback
}

cmd_dry_run() {
    check_root
    check_os
    load_modules

    echo -e "${BOLD}Agent Machine v${VERSION} — Dry Run${NC}"
    echo -e "${CYAN}Showing what would be changed (no modifications made)${NC}"
    echo ""

    detect_hardware
    detect_user

    log_section "Performance Changes"
    local current_swap_mb
    current_swap_mb=$(awk '/SwapTotal/ {print int($2/1024)}' /proc/meminfo)
    if [[ $current_swap_mb -eq 0 ]]; then
        echo "  • swap: create swap file (none detected)"
    else
        echo "  • swap: ${current_swap_mb}MB already exists (no changes)"
    fi
    echo "  • zswap: enable with zstd compression, ${ZSWAP_POOL_PCT}% pool"
    echo "  • sysctl: 40+ kernel parameters (BBR, memory, network, scheduler)"
    echo "  • systemd-oomd: proactive OOM defense (60% pressure threshold)"
    echo "  • cgroups: SSH protected, user slice MemHigh=${USER_MEM_HIGH} MemMax=${USER_MEM_MAX}"
    echo "  • filesystem: noatime, THP=madvise, I/O scheduler rules"
    echo "  • monitoring: btop, atop, iotop-c, bpfcc-tools, psi-watch"

    log_section "Security Changes"
    echo "  • SSH: MaxAuthTries=3, no root login, key-only (if keys found)"
    echo "  • firewall: ufw deny incoming, allow SSH/HTTP/HTTPS"
    echo "  • fail2ban: 5 attempts → 1h ban"
    echo "  • services: disable snapd, cups, avahi, ModemManager, bluetooth, multipathd"
    echo "  • updates: automatic security patches (no auto-reboot)"

    log_section "Files Modified"
    if [[ $current_swap_mb -eq 0 ]]; then
        echo "  • /swapfile (new)"
    fi
    echo "  • /etc/sysctl.d/99-agent-machine.conf (new)"
    echo "  • /etc/default/grub (append zswap params)"
    echo "  • /etc/fstab (add noatime)"
    echo "  • /etc/systemd/oomd.conf (new)"
    echo "  • /etc/systemd/system/ssh.service.d/agent-machine.conf (new)"
    echo "  • /etc/systemd/system/user-${TARGET_UID}.slice.d/agent-machine.conf (new)"
    echo "  • /etc/systemd/system/-.slice.d/oomd.conf (new)"
    echo "  • /etc/systemd/system/user@.service.d/oomd.conf (new)"
    echo "  • /etc/ssh/sshd_config.d/agent-machine.conf (new)"
    echo "  • /etc/fail2ban/jail.local (new/overwrite)"
    echo "  • /etc/udev/rules.d/60-agent-machine-io.rules (new)"
    echo "  • /etc/tmpfiles.d/agent-machine-thp.conf (new)"
    echo "  • /usr/local/bin/psi-watch (new)"

    echo ""
    echo -e "Run ${BOLD}sudo bash install.sh${NC} to apply these changes."
    echo -e "All changes can be reverted with ${BOLD}sudo bash install.sh --rollback${NC}"
}

# =============================================================================
# Main
# =============================================================================

main() {
    case "${1:-}" in
        --check)      cmd_check ;;
        --rollback)   cmd_rollback ;;
        --perf-only)  cmd_perf_only ;;
        --sec-only)   cmd_sec_only ;;
        --dry-run)    cmd_dry_run ;;
        --version|-v) echo "agent-machine v${VERSION}" ;;
        --help|-h)
            echo "Agent Machine v${VERSION} — Performance + Security for AI VMs"
            echo ""
            echo "Usage: sudo bash install.sh [OPTION]"
            echo ""
            echo "Options:"
            echo "  (no args)     Full install (performance + security)"
            echo "  --perf-only   Performance tuning only"
            echo "  --sec-only    Security hardening only"
            echo "  --check       Verify current tuning"
            echo "  --rollback    Revert all changes"
            echo "  --dry-run     Show what would change"
            echo "  --version     Show version"
            echo "  --help        Show this help"
            echo ""
            echo "One-liner:"
            echo "  curl -fsSL https://raw.githubusercontent.com/craigvandotcom/agent-machine/main/install.sh | sudo bash"
            ;;
        *)            cmd_full ;;
    esac
}

main "$@"
