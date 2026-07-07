# shell-arious

This repository is my personal shell and systems toolbox. It started as a place to save Linux commands, setup notes, and small scripts while I was learning. I am keeping that history, but the repo is now organized so the useful tools are easier to find and the rougher notes are clearly separated.

The goal is not to make every script look over-engineered. The goal is to keep practical scripts with safer defaults, readable usage examples, and enough documentation that someone else can understand what each file is for.

## Layout

```text
automation/
  Scripts for repeatable system maintenance and local audit tasks.

docs/
  Notes about script safety and repo conventions.

notes/
  Older setup notes, drafts, and recovery snippets that are useful but not all ready-to-run.

scripts/
  General-purpose scripts that can be run directly after review.

utils/
  Small command-line helpers for common troubleshooting tasks.
```

## Good Starting Points

- `utils/env-check.sh` checks whether common DevOps tools are installed.
- `utils/port-check.sh` checks whether a TCP port is listening locally.
- `utils/disk-usage-report.sh` gives a quick read-only disk usage summary.
- `automation/package-audit.sh` summarizes OS/package state without changing the machine.
- `scripts/text-explorer.sh` searches and samples text files from a directory.

## Before Running Scripts

Read the script first, especially if it uses `sudo`, package managers, service commands, or file deletion. Some older notes in this repo were written for one machine or one lab setup and should be treated as references until reviewed.

For runnable shell scripts:

```bash
chmod +x path/to/script.sh
./path/to/script.sh --help
```

For cleanup or maintenance scripts, prefer dry-run mode first when available.

## What This Repo Shows

- Bash scripting for real workstation and Linux administration tasks
- Basic validation and help output
- Read-only troubleshooting utilities
- Safer handling of scripts that can change the system
- Keeping rough notes without pretending they are production-ready tools

## Next Improvements

- Add ShellCheck coverage
- Add examples for each script
- Continue converting useful `.txt` notes into reviewed `.sh` scripts
- Add dry-run modes to any script that changes files or packages
- Keep personal paths and machine-specific values out of committed scripts