# Decisions

## Audit before recommending changes

The toolkit records system state and generates a separate plan. It does not
infer that a running service, installed package, or enabled feature is wasteful.
Review recommendations require both audit evidence and an explicit policy
candidate in `config.psd1`.

## Protected virtualization and security

WSL 2 and Virtual Machine Platform are policy requirements. Hyper-V components
and Windows Hypervisor Platform are inventoried because dependencies vary, not
treated as optimization targets. Memory Integrity (HVCI), Defender, and Firewall
are security controls and are never disable recommendations. Microsoft describes
Memory Integrity as virtualization-based protection for kernel code integrity:
https://learn.microsoft.com/windows-hardware/design/device-experiences/oem-hvci-enablement

Windows Update, Microsoft Store support, networking, recovery, audio, Bluetooth,
GPU drivers, Secure Boot, and TPM are outside change scope.

## Community utility research

ChrisTitusTech WinUtil was reviewed as a current public reference:
https://github.com/ChrisTitusTech/winutil

Useful ideas include visible presets/policy, grouping related observations, and
making actions inspectable. This project does not adopt WinUtil's broad tweak
presets, mass package operations, update-control options, or system-wide
administrative assumption. Those operations span security, Store applications,
gaming, hardware utilities, and virtualization dependencies too broadly for an
audit-first workstation policy.

WinUtil documents `irm ... | iex` and dynamic script-block execution as launch
options. This project does not download or execute remote code. Source is kept
local and reviewable.

## Delivery Optimization and power policy

Delivery Optimization is inventoried rather than disabled. Microsoft documents
that it supplies Windows Update and Store content and recommends choosing policy
from network topology and organization needs:
https://learn.microsoft.com/windows/deployment/do/delivery-optimization-configure

Power settings are captured with `powercfg`. A non-balanced plan may justify a
`Review` recommendation only when the collected setting and local policy give a
specific alternative; processor minimum state is never raised to 100 percent as
an optimization.

## Page file, Search, and optional features

A system-managed page file is classified `DoNotChange` absent measured evidence.
Windows Search should be narrowed before considering disablement. Optional
features are reviewable only after dependency analysis. Folklore tweaks such as
HPET changes, timer hacks, blanket service disables, core-parking changes, and
arbitrary network registry edits are intentionally absent.

## Data handling

Reports stay under ignored `output/`. They may contain account names, paths,
application inventory, task names, and device identifiers and must not be
committed.
