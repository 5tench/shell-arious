# Windows workstation baseline

A small, read-only PowerShell toolkit for auditing a Windows 11 Enterprise
workstation and producing evidence-based recommendations. It does not apply
optimizations.

## Requirements

- Windows 11
- Windows PowerShell 5.1 or PowerShell 7
- Some probes return `Unavailable` without elevation; run from an elevated
  terminal when a fuller inventory is needed.

## Usage

```powershell
.\baseline.ps1 -Mode Audit
.\baseline.ps1 -Mode Plan
.\baseline.ps1 -Mode Plan -AuditPath .\output\audit-20260101-120000.json
```

Reports are written to the ignored `output/` directory. JSON contains the full
structured inventory; Markdown is a shorter operator-readable view. Treat both
as sensitive because application paths, user names, and device identifiers can
appear in them.

`Apply` and `Rollback` deliberately exit with code 2 and do nothing. Other
failures exit with code 1.

Edit `config.psd1` to express workstation policy. Arrays must remain arrays
(use `@()` for empty values), numeric settings must be non-negative integers,
and sampling/count settings must be positive.

## Validation

```powershell
Invoke-Pester .\tests
Invoke-ScriptAnalyzer . -Recurse
```

The audit is Windows-only. Tests and static analysis require the Pester and
PSScriptAnalyzer modules, respectively.
