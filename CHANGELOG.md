# 📝 Changelog

All notable changes to the **CHASE** project will be documented in this file.

## [2.0.0] - 2026-05-21

This release marks a major architectural rewrite and modernization upgrade of the security auditor (formerly known as MARIE) to **CHASE** (Configuration & Host Audit Security Evaluator).

### Added
* **Dynamic Module Discovery**: Implemented a scanning mechanism to auto-load modules from the `modules/` directory based on priority header tags.
* **OS Auto-Detection**: Integrated `/etc/os-release` parsing to dynamically adapt commands for Debian, RHEL, and Alpine families.
* **Vampire Cyber-Console TUI**: Redesigned the entire command line interface with gradient red/charcoal box-drawings and a live-updating scanning status layout.
* **Interactive Remediation Wizard**: Added the `--remediate` / `-r` CLI flag allowing selective fixing of security vulnerabilities interactively.
* **Premium SOC Operations HTML Report**: Redesigned the reporting template to output a space-themed cyber dashboard featuring:
  * A circular SVG hardening score gauge.
  * Collapsible finding cards with glowing borders for high/critical threats.
  * Real-time search and dual filters (severity and domain).
  * An on-the-fly client-side remediation script download center.
* **GitHub Repository Assets**: Added high-quality `README.md`, `LICENSE`, and `CHANGELOG.md`.

### Fixed
* Corrected duplicate UID checks to prioritize duplicate UID 0 root accounts as CRITICAL instead of HIGH.
* Replaced loose regex matches with strict word boundary matches for shell escape commands in sudoers.
* Standardized text trimming of interactive shell paths in service account audits to avoid misidentification.

### Removed
* Deleted old legacy, unneeded files from the MARIE naming schema.
