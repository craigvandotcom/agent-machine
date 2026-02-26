# Agent Machine

One command to make your cloud server ready for AI coding agents.

## The Problem

You rent a cloud server. You install Claude Code (or Cursor, Codex, Copilot, etc.). You start working. Then:

- **Your server freezes** — the AI agent used all the memory and you can't even SSH in to fix it
- **You lose your SSH session** — the system killed it to save memory for the AI process
- **Everything is slow** — the default Linux settings are designed for general use, not AI workloads
- **You're exposed** — stock servers have weak SSH settings, no firewall, and unnecessary services running

Agent Machine fixes all of this in about 60 seconds.

## What You Get

**Your server won't freeze anymore.** A three-layer defense system manages memory automatically:
1. When memory gets high, processes slow down (instead of crashing)
2. If that's not enough, the worst offender gets killed (not SSH, not your services — the thing using the most)
3. As a last resort, the kernel steps in (but you'll almost never reach this)

**Your SSH connection is protected.** Even under maximum load, SSH keeps working. You'll always be able to log in.

**Network is faster.** Modern TCP settings (~30% throughput improvement) and better buffer sizing.

**Disk I/O is smarter.** Fewer unnecessary writes, better scheduling for SSDs.

**Memory goes further.** Compressed swap means ~3x more effective memory before hitting disk.

**Security is handled.** Firewall, SSH hardening, brute force protection, automatic security updates — all configured with safe defaults.

## Quick Start

See what it would do first (no changes made):

```bash
curl -fsSL https://raw.githubusercontent.com/craigvandotcom/agent-machine/main/install.sh | sudo bash -s -- --dry-run
```

Then run it:

```bash
curl -fsSL https://raw.githubusercontent.com/craigvandotcom/agent-machine/main/install.sh | sudo bash
```

Or clone and run:

```bash
git clone https://github.com/craigvandotcom/agent-machine.git
cd agent-machine
sudo bash install.sh
```

Don't like it? Undo everything:

```bash
sudo bash install.sh --rollback
```

## Options

```bash
sudo bash install.sh              # Full install (performance + security)
sudo bash install.sh --perf-only  # Performance only (no security changes)
sudo bash install.sh --sec-only   # Security only (no performance changes)
sudo bash install.sh --check      # Check what's currently applied
sudo bash install.sh --dry-run    # Preview changes without applying them
sudo bash install.sh --rollback   # Undo everything
```

## What It Actually Does

Everything auto-detects your hardware. No configuration needed.

### Performance

| Change | Plain English | Technical Detail |
|--------|---------------|------------------|
| **Swap file** | Creates emergency overflow memory if none exists | Sized per Ubuntu formula, persisted in fstab |
| **Compressed swap** | Memory goes ~3x further before hitting disk | zswap with zstd, 20% RAM pool |
| **Memory defense** | Three layers prevent freezing | MemoryHigh → systemd-oomd → kernel OOM |
| **Network speed** | Faster downloads, better SSH responsiveness | TCP BBR, optimized buffers |
| **Disk speed** | Fewer unnecessary disk writes | noatime, SSD-optimized writeback, I/O scheduler rules |
| **SSH protection** | SSH always works, even under memory pressure | cgroup priority, OOM omit, guaranteed memory |
| **Monitoring** | Tools to see what's happening | btop, atop, psi-watch |

### Security

| Change | Plain English | Technical Detail |
|--------|---------------|------------------|
| **SSH hardening** | Harder to break into | Key-only auth (if keys present), no root login, rate limiting |
| **Firewall** | Block unwanted connections | ufw: deny incoming, allow SSH + HTTP/HTTPS |
| **Brute force protection** | Auto-ban repeated failed logins | fail2ban: 5 attempts → 1 hour ban |
| **Service cleanup** | Disable things you don't need | snapd, cups, avahi, bluetooth, etc. |
| **Auto updates** | Security patches install automatically | unattended-upgrades, no auto-reboot |

## Safety

This is designed to be safe to run:

- **Preview first:** `--dry-run` shows every change before applying
- **Full undo:** `--rollback` reverts everything to the pre-install state
- **SSH is sacred:** Password auth is only disabled if SSH keys are already set up
- **Firewall is careful:** SSH is always allowed before the firewall turns on
- **Non-destructive:** Uses config drop-in files, not inline edits to system configs
- **Idempotent:** Safe to run multiple times — it detects what's already applied

## Requirements

- **OS:** Ubuntu 22.04+ or Debian 12+
- **Access:** Root / sudo
- **Providers:** Any (Hetzner, DigitalOcean, AWS, GCP, Linode, Vultr, etc.)
- **Hardware:** 2GB+ RAM, any CPU count, SSD or HDD

## What It Doesn't Do

- Install AI tools (Claude Code, Python, Node.js, etc.) — bring your own stack
- Require a reboot (most changes apply immediately)
- Phone home or collect data
- Touch your application code or configs

## After Install

Useful commands:

```bash
# Check everything is applied
sudo bash install.sh --check

# Watch system pressure in real-time
sudo psi-watch

# Interactive system monitor
btop

# See who's been banned
sudo fail2ban-client status sshd

# View OOM defense logs
journalctl -u systemd-oomd -f
```

## License

MIT
