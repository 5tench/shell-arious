# Script Index

| Script | Purpose | Changes System? | Key Arguments |
|---|---|---:|---|
| `automation/package-audit.sh` | Read-only OS and package summary with runtime package-manager detection. | No | none |
| `automation/update_OS.sh` | Preview or apply package updates using the detected package manager. | Only with `--apply` | `--apply` |
| `scripts/system-triage.sh` | First-pass Linux health snapshot. | No | `--services`, `--since`, `--output`, `--json` |
| `scripts/service-doctor.sh` | Diagnose one systemd service with common service-name aliases. | No | service name, `--since`, `--logs` |
| `scripts/log-hunter.sh` | Search files or journal output. | No | `--path`, `--pattern`, `--journal`, `--unit`, `--since`, `--top` |
| `scripts/permission-audit.sh` | Report risky filesystem permissions. | No | `--path`, `--suid`, `--world-writable`, `--exclude` |
| `scripts/user-access-audit.sh` | Review local users, sudo/wheel access, homes, and SSH keys. | No | `--csv`, `--include-system` |
| `scripts/process-port-map.sh` | Map listening TCP ports to processes using `ss`, `netstat`, or `lsof`. | No | `--port`, `--process`, `--json` |
| `scripts/cron-timer-audit.sh` | Show cron jobs and systemd timers across common cron layouts. | No | `--user`, `--timers` |
| `scripts/cert-check.sh` | Check TLS certificate expiration. | No | host, `--file`, `--port`, `--warn-days` |
| `scripts/path-audit.sh` | Inspect PATH hygiene. | No | `--check-writable` |
| `scripts/install-guest-additions.sh` | Install VirtualBox Guest Additions from a mounted ISO. | Yes | mount path |
| `scripts/text-explorer.sh` | Search and sample text files. | No | directory, pattern, field, delimiter, file pattern |
| `utils/bash_cleanUp.sh` | Local cleanup helper. | Only with `--apply` | `--apply` |
| `utils/disk-usage-report.sh` | Disk usage summary. | No | path, top count |
| `utils/env-check.sh` | Check for common CLI tools. | No | tool names |
| `utils/fixNvidiaDriverExternalMonitors.sh` | NVIDIA/Mesa troubleshooting command runner. | Only with `--apply` | `--apply` |
| `utils/pdfcompression.sh` | Compress a PDF with Ghostscript. | Writes output file | input, output, quality |
| `utils/port-check.sh` | Check one local TCP port. | No | port |

Package-related scripts stay in one file and detect the available package manager at runtime. The rest of the troubleshooting scripts stay mostly distro-neutral and branch only when a command or path actually differs.