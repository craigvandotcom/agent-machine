# Agent Machine

Turn a stock Ubuntu VPS into a hardened, high-performance AI workstation. One command.

Built for running AI coding agents (Claude Code, Cursor, Codex, etc.) on cloud VMs — where stock OS defaults waste 20-40% of your machine's potential and leave it vulnerable.

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/craigvandotcom/agent-machine/main/install.sh | sudo bash
```

Or clone and run:

```bash
git clone https://github.com/craigvandotcom/agent-machine.git
cd agent-machine
sudo bash install.sh
```

## What It Does

### Performance

| Feature | What | Why |
|---------|------|-----|
| **zswap** | Compressed swap in RAM (zstd, ~3x ratio) | Sub-microsecond page recovery vs ~100ms from disk |
| **BBR** | TCP congestion control | ~30% throughput improvement, better SSH responsiveness |
| **systemd-oomd** | Proactive OOM defense | Kills worst offender before kernel freezes the machine |
| **cgroup priorities** | SSH/system protected, AI sessions managed | Never lose SSH access during memory pressure |
| **Kernel tuning** | 40+ sysctl params (memory, network, I/O, scheduler) | Calibrated for AI workloads, not generic desktop |
| **Filesystem** | noatime, THP=madvise, I/O scheduler rules | Less disk overhead, smarter huge pages |
| **Monitoring** | btop, atop, psi-watch | See what's actually happening |

### Security

| Feature | What | Why |
|---------|------|-----|
| **SSH hardening** | Key-only auth, no root, rate limiting | Blocks 99% of automated attacks |
| **Firewall** | ufw: deny incoming, allow SSH/HTTP/HTTPS | Minimal attack surface |
| **fail2ban** | 5 failed attempts → 1h ban | Brute force protection |
| **Service cleanup** | Disable snapd, cups, avahi, bluetooth, etc. | Less running code = fewer vulnerabilities |
| **Auto updates** | Automatic security patches | Unattended CVE coverage, no auto-reboot |

### Three-Layer Memory Defense

The #1 problem with AI agents on VMs: they eat all the RAM, the machine freezes, and you lose SSH access.

```
Layer 1: MemoryHigh    → throttle (slow processes down)
Layer 2: systemd-oomd  → surgical kill (remove worst offender)
Layer 3: kernel OOM    → emergency kill (last resort, prevents freeze)
```

This is modeled after the immune system — graduated response, not all-or-nothing.

## Options

```bash
sudo bash install.sh              # Full install (performance + security)
sudo bash install.sh --perf-only  # Performance tuning only
sudo bash install.sh --sec-only   # Security hardening only
sudo bash install.sh --check      # Verify current state
sudo bash install.sh --rollback   # Revert all changes
sudo bash install.sh --dry-run    # Show what would change (no modifications)
```

## Hardware Auto-Detection

Everything scales to your hardware. No configuration needed.

- **RAM**: Memory limits, min_free_kbytes, zswap pool size
- **Disk**: SSD vs HDD detection → different dirty ratios, I/O schedulers
- **CPUs**: Scheduler tuning scaled to core count
- **Kernel**: Feature detection (BBR, MGLRU, PSI availability)
- **User**: Auto-detects primary non-root user for cgroup setup

Tested on: 4GB-64GB RAM, 2-32 CPUs, SSD/NVMe, Ubuntu 22.04/24.04, Debian 12.

## Safety

- **Full rollback**: `sudo bash install.sh --rollback` reverts every change
- **Pre-flight state saved**: All original configs backed up before modification
- **SSH safety**: Never disables password auth unless SSH keys are already set up
- **Firewall safety**: SSH is always allowed before enabling firewall
- **Dry run**: `--dry-run` shows exactly what would change
- **Non-destructive**: Uses config drop-ins (`.d/` directories), not inline edits

## What It Doesn't Do

- Install AI tools (Claude Code, Python, Node.js, etc.) — that's your stack
- Configure application-level settings
- Require reboots (most changes apply immediately, a few persist on reboot)
- Phone home or collect telemetry

## Supported

- Ubuntu 22.04, 24.04 (primary target)
- Debian 12+ (works, less tested)
- Kernel 5.15+ (6.x recommended for full feature set)
- Any VPS provider (Hetzner, DigitalOcean, AWS, GCP, etc.)

## License

MIT
