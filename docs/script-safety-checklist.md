# Script Safety Checklist

This is the quick review I want to do before running scripts from this repo or from anywhere else.

## First Pass

- Read the whole script before running it.
- Check whether it needs root or administrator privileges.
- Look for commands that remove files, install packages, restart services, mount filesystems, or write to system paths.
- Check whether paths are hardcoded to one machine or user.
- Prefer read-only or dry-run mode first when available.

## Commands Worth Slowing Down For

```bash
grep -nE 'sudo|rm -rf|apt|dnf|yum|systemctl|mkfs|mount|umount|chown|chmod' path/to/script
```

For PowerShell:

```powershell
Select-String -Path .\script.ps1 -Pattern 'Remove-Item|Set-Content|Copy-Item|Move-Item|Restart-Service|Stop-Service|Format-Volume'
```

## Safer Script Habits

- Use `set -euo pipefail` for Bash scripts when practical.
- Quote variables that may contain spaces.
- Validate arguments before using them.
- Print what the script is going to do before it does it.
- Add `--help` output for scripts with arguments.
- Make destructive behavior opt-in with `--apply`, `--yes`, or `--force`.

## Before Committing

- Remove personal paths and machine names.
- Replace secrets, tokens, account IDs, and private resource names.
- Keep examples generic.
- Run syntax checks where possible.