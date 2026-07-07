# Hidden Mount Scanner

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell: Bash](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![Platform: Linux](https://img.shields.io/badge/Platform-Linux-blue.svg)](https://www.linux.org/)

**Discover hidden data lurking underneath mount points on Linux systems.**

## The Problem

When a filesystem is mounted over a directory (like NFS over `/data`), any existing files in that directory become **invisible** — but they still consume disk space. This commonly happens during storage migrations when data is copied but never deleted from the original location.

Symptoms:
- `df` shows disk is 80% full
- `du` shows only 40% of space used
- **Where's the other 40%?** Hidden under mount points.

## How It Works

The scanner uses bind mounts to create an alternate view of the root filesystem, bypassing the normal mount table to reveal data hidden underneath mount points.

```
Normal view:       /data → NFS mount (shows NFS contents)
Bind mount view:   /mnt/root_check/data → Original local data (reveals hidden files!)
```

## Installation

```bash
# Download
curl -O https://raw.githubusercontent.com/yourusername/hidden-mount-scanner/main/hidden-mount-scanner.sh

# Make executable
chmod +x hidden-mount-scanner.sh

# Run (requires root)
sudo ./hidden-mount-scanner.sh
```

## Usage

```bash
# Scan all mount points
sudo ./hidden-mount-scanner.sh

# Scan specific mount point
sudo ./hidden-mount-scanner.sh -t /data

# Deep scan with file details
sudo ./hidden-mount-scanner.sh -d

# JSON output for automation
sudo ./hidden-mount-scanner.sh -f json -o report.json

# Quick fleet scan
sudo ./hidden-mount-scanner.sh -q --no-color
```

### Options

| Option | Description |
|--------|-------------|
| `-t, --target PATH` | Scan specific mount point only |
| `-f, --format FORMAT` | Output format: text, json, csv |
| `-o, --output FILE` | Write output to file |
| `-d, --deep` | Deep scan: file counts, oldest/newest files |
| `-q, --quick` | Quick scan: sizes only |
| `-m, --min-size KB` | Minimum size to report (default: 4 KB) |
| `-v, --verbose` | Verbose output with debug info |
| `--no-color` | Disable colored output |
| `-h, --help` | Show help message |

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success, no hidden data found |
| 1 | Success, hidden data found |
| 2 | Error (permissions, invalid options, etc.) |

## Example Output

```
═══════════════════════════════════════════════════════════════════════════════
  HIDDEN MOUNT SCANNER v1.0.0
═══════════════════════════════════════════════════════════════════════════════

  Hostname:     server01.example.com
  Date:         Mon Feb 10 14:30:00 UTC 2026
  Scan Depth:   standard

  *** READ-ONLY SCAN - NO CHANGES MADE ***

───────────────────────────────────────────────────────────────────────────────

[FOUND] Hidden data under /dbshare
    Size:        9.2G (9646080 KB)
    Mount Type:  nfs4
    Mount From:  fs-xxxxx.efs.us-east-1.amazonaws.com:/

───────────────────────────────────────────────────────────────────────────────
  SUMMARY
───────────────────────────────────────────────────────────────────────────────

  Mount points scanned:   12
  With hidden data:       1
  Total hidden size:      9.2G

  ⚠ HIDDEN DATA DETECTED

  To investigate further, use bind mount:
    sudo mkdir -p /mnt/root_check
    sudo mount --bind / /mnt/root_check
    ls -la /mnt/root_check/<mount_point>/
    sudo umount /mnt/root_check

═══════════════════════════════════════════════════════════════════════════════
```

## JSON Output

```json
{
    "scanner_version": "1.0.0",
    "hostname": "server01.example.com",
    "timestamp": "2026-02-10T14:30:00+00:00",
    "scan_depth": "deep",
    "summary": {
        "mounts_scanned": 12,
        "mounts_with_hidden_data": 1,
        "total_hidden_bytes": 9877585920,
        "total_hidden_human": "9.2G"
    },
    "findings": [
        {
            "mount_point": "/dbshare",
            "size_bytes": 9877585920,
            "size_human": "9.2G",
            "mount_fstype": "nfs4",
            "mount_source": "fs-xxxxx.efs.us-east-1.amazonaws.com:/",
            "file_count": 1523,
            "dir_count": 42,
            "oldest_file": "1995-03-15 ...",
            "newest_file": "2020-01-10 ..."
        }
    ]
}
```

## Fleet Scanning

For scanning multiple servers, use the JSON or CSV output:

```bash
# On each server
sudo ./hidden-mount-scanner.sh -f json -q > /tmp/scan_$(hostname).json

# Collect results
for server in server{1..10}; do
    ssh $server 'sudo /tmp/hidden-mount-scanner.sh -f json -q'
done | jq -s '.'
```

## Safety

- **READ-ONLY**: No files are modified or deleted
- **Temporary**: Bind mounts are auto-cleaned on exit
- **Non-invasive**: Works on production systems
- **Trap handling**: Cleanup runs even on Ctrl+C

## Use Cases

1. **Troubleshooting**: Explain df vs du discrepancies
2. **Storage Migrations**: Find orphaned data after NFS moves
3. **Audits**: Discover untracked/unmonitored data
4. **Security**: Find hidden files on servers
5. **Capacity Planning**: Identify reclaimable space

## How to Clean Up Hidden Data

Once you've identified hidden data:

```bash
# 1. Create bind mount (read-write this time)
sudo mkdir -p /mnt/root_check
sudo mount --bind / /mnt/root_check

# 2. Review the data
ls -la /mnt/root_check/<mount_point>/

# 3. Delete if appropriate (BE CAREFUL!)
sudo rm -rf /mnt/root_check/<mount_point>/*

# 4. Cleanup
sudo umount /mnt/root_check
sudo rmdir /mnt/root_check

# 5. Verify space recovered
df -h /
```

## Requirements

- Linux (tested on RHEL 7/8, Ubuntu 18.04+, Debian 10+)
- Bash 4.0+
- Root/sudo privileges
- Standard utilities: mount, findmnt, du, df, find, awk, grep

## Background Reading

- [Baeldung: Understanding Bind Mounts](https://www.baeldung.com/linux/bind-mounts)
- [ServerFault: Disk full, du tells different](https://serverfault.com/questions/275206/disk-full-du-tells-different-how-to-further-investigate)

## Contributing

Pull requests welcome! Please:
1. Fork the repo
2. Create a feature branch
3. Add tests if applicable
4. Submit PR with clear description

## License

MIT License - see [LICENSE](LICENSE) file.

## Author

Your Name
- GitHub: [@yourusername](https://github.com/yourusername)
- LinkedIn: [yourprofile](https://linkedin.com/in/yourprofile)

---

*Found this useful? Give it a ⭐ on GitHub!*
