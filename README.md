# 🛡️ CHASE — Configuration & Host Audit Security Evaluator

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/version-2.0-red.svg)](https://github.com/deepmind/chase)
[![Platform](https://img.shields.io/badge/platform-linux-lightgrey.svg)](https://www.linux.org/)

**CHASE** is a modular, lightweight, high-performance cybersecurity auditing tool written entirely in pure Bash. It performs comprehensive local system audits mapped against CIS-inspired hardening standards, compiles detailed machine-readable reports, and features an interactive terminal remediation wizard to repair insecure configurations in real-time.

---

## 🚀 Key Features

* **Dynamic Module Discovery**: Automatically scans and prioritizes audit module plugins dynamically at runtime using custom header metadata.
* **OS Auto-Detection**: Seamlessly identifies targets under Debian, Ubuntu, RHEL, CentOS, Rocky Linux, AlmaLinux, and Alpine families to adapt package installation commands and paths.
* **Vampire Cyber-Console TUI**: A beautiful terminal interface displaying real-time scan statuses via a single-frame box-drawn dashboard, complete with live findings scoreboards.
* **Interactive Remediation Wizard**: Allows administrators to inspect each security vulnerability on the command line and selectively apply the corresponding remediation fix.
* **Premium SOC Operations Dashboard**: Generates a self-contained, responsive HTML report featuring:
  * A dynamic **Hardening Posture Gauge** displaying the security score.
  * Real-time search and dual-filtering (by severity and domain category).
  * An on-the-fly **Remediation Script Compiler** allowing users to download a compiled bash script of all non-suppressed remediation actions.
* **Compliance Levels**: Supports CIS level 1 and level 2 benchmark levels natively.

---

## 🗺️ Architecture Overview

```text
               ┌──────────────────────────────┐
               │    Administrator / Operator  │
               └──────────────┬───────────────┘
                              │
                        [ ./chase.sh ]
                              │
                              ▼
               ┌──────────────────────────────┐
               │      CHASE Core Engine       │
               │   (Preflight & OS Detect)    │
               └──────────────┬───────────────┘
                              │ (Dynamic Discovery)
                              ▼
               ┌──────────────────────────────┐
               │      Dynamic Modules         │
               │  [IAM] [Network] [Filesystem]│
               │    [Software] [Crypto]       │
               └──────────────┬───────────────┘
                              │
                              ▼
               ┌──────────────────────────────┐
               │    Live Status Dashboard     │
               └──────────────┬───────────────┘
                              │
            ┌─────────────────┴─────────────────┐
            ▼                                   ▼
┌───────────────────────┐           ┌───────────────────────┐
│     JSON Report       │           │   HTML SOC Dashboard  │
│ (chase_report_*.json) │           │ (chase_report_*.html) │
└───────────────────────┘           └───────────────────────┘
            │                                   │
            ▼                                   ▼
┌───────────────────────┐           ┌───────────────────────┐
│ Syslog Security Logs  │           │  Remediation Script   │
│  (syslog / journald)  │           │ (chase_remediations.sh)│
└───────────────────────┘           └───────────────────────┘
```

---

## 📦 Installation & Quick Start

### Prerequisites
* Bash 4.0 or greater.
* Root privileges on the target system.

### Quick Start
1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/chase.git
   cd chase
   ```
2. Execute a full security scan:
   ```bash
   sudo ./chase.sh
   ```
3. Run with the interactive remediation wizard enabled:
   ```bash
   sudo ./chase.sh --remediate
   ```

---

## 🛠️ Command-Line Interface Usage

```text
Usage: sudo ./chase.sh [OPTIONS]

Options:
  --output-dir DIR    Save reports to DIR (default: /var/log/chase)
  --modules LIST      Comma-separated module list (short or full names)
                        Short names : iam, filesystem, network, software, persistence
                        Examples    : --modules iam,network
  --quick             Skip slow filesystem traversal (world-writable scans)
  --delta             Show diff vs last scan findings
  --no-colour         Plain text output (disabled ANSI colors)
  --verbose, -v       Verbose output with detailed logs
  --quiet, -q         Minimal output (only critical alerts and summary)
  --remediate, -r     Run interactive remediation wizard after scan
  --version           Show version and exit
  --help, -h          Show this message
```

---

## ⚙️ Configuration & Customization

The system parameters are stored in `config/chase.conf`. You can customize:
* `REPORT_DIR`: Directory where HTML, JSON, and baseline logs are written.
* `BENCHMARK`: Choose compliance level (`cis_level1` or `cis_level2`).
* `SYSLOG_ENABLED`: Set to `1` to output findings directly to system logs.
* `EXCLUDE_DIRS`: File paths and partitions to prune during security traversal.

To suppress specific warnings, add patterns or finding titles to `config/suppressions.list` (one regex pattern per line).

---

## 🧪 Running Automated Tests

CHASE uses [BATS](https://github.com/bats-core/bats-core) (Bash Automated Testing System) to assert the correctness of its parsing modules, OS helpers, and audit logic:

```bash
./run_tests.sh
```

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](file:///home/ubuntu/CHASE/LICENSE) file for details.
