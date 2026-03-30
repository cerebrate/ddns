---
description: "Use when editing Azure Functions PowerShell run.ps1 files for DNS updates, including parameter parsing, A and AAAA record update logic, and response handling. Enforces symmetry, safety checks, and minimal-risk changes."
name: "PowerShell Function Safety Rules"
applyTo: "UpdateStargate*/run.ps1"
---
# PowerShell Function Safety Rules

- Keep IPv4 and IPv6 handlers structurally mirrored. If one run.ps1 changes request parsing, branching, or response text, apply the equivalent change to the sibling function unless a type-specific difference is required.
- Preserve valid type-specific differences only:
  - IPv4 uses RecordType A and Ipv4Address.
  - IPv6 uses RecordType AAAA and Ipv6Address.
- Require complete inputs before DNS operations. Validate Name, Zone, and reqIP are present after query and body fallback parsing.
- Never perform DNS writes when inputs are missing or invalid. Return BadRequest with a clear operator-facing message instead.
- Keep changes minimal and local to the requested behavior. Do not add unrelated refactors in run.ps1 files.
- Preserve existing operational assumptions unless explicitly asked to change them:
  - Resource group usage and TTL behavior
  - Function response contract (success and bad request paths)
- Use explicit branch logging with Write-Host for lookup, no-op, update, create, and error paths.
- Do not log secrets or sensitive tokens in request data.
- For any intentional divergence between the two run.ps1 files, document the reason in the final summary.

See [workspace guidance](../copilot-instructions.md) for project-wide conventions and deployment assumptions.
