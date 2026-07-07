# Conventions

This repo favors practical Bash over clever Bash.

## One Script Per Task

Do not create separate Ubuntu, Debian, RHEL, Fedora, Rocky, or Arch copies of the same script. Keep one script per task and detect the local tools at runtime when the task needs that information.

Good pattern:

```bash
if command_exists dnf; then
  PKG_MANAGER="dnf"
elif command_exists apt-get; then
  PKG_MANAGER="apt-get"
fi
```

Use `/etc/os-release` for reporting and distro context. Prefer `command -v` when the script needs to know whether a command can actually run.

## Bash Style

- Use `#!/usr/bin/env bash` for runnable shell scripts.
- Use `set -euo pipefail` unless there is a clear reason not to.
- Quote variables by default.
- Keep functions small and named for the job they do.
- Prefer readable conditionals over dense one-liners.
- Use plain heredoc help text in `show_help()`.

## Safety Defaults

- Inspection scripts should be read-only.
- Scripts that can change the system should require an explicit flag such as `--apply` or `--update`.
- Do not delete files, restart services, change ownership, or install packages from a default run.
- Print clear messages before doing anything that changes state.

## Runtime Detection

- Package scripts should detect `apt-get`, `apt`, `dnf`, `yum`, `zypper`, or `pacman` when useful.
- Service scripts can account for common name differences such as `ssh`/`sshd`, `cron`/`crond`, and `apache2`/`httpd`.
- Cron scripts should check common paths used by Debian and RHEL-family systems when readable.
- Most troubleshooting scripts should stay distro-neutral and use common Linux tools.

## Arguments

- Support `--help` and `-h`.
- Validate required arguments.
- Validate numeric arguments such as ports, counts, and day thresholds.
- Avoid hardcoded user paths, hostnames, account names, or environment-specific values.

## Output

- Human-readable output is the default.
- Keep section headers simple.
- Avoid noisy banners.
- Add JSON only when it stays simple and useful.
- If an optional command is missing, warn and continue when safe.

## Dependencies

- Check optional commands before using them.
- Prefer common Linux tools such as `awk`, `grep`, `find`, `sort`, `ps`, `df`, `du`, `ss`, `getent`, `stat`, and `openssl`.
- Do not install missing tools from an inspection script.

## Exit Codes

- `0`: completed successfully.
- `1`: completed but found a warning condition, or a checked item was not present.
- `2`: invalid arguments or usage.
- `3+`: dependency or environment problem.