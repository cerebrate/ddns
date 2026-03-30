---
description: "Apply symmetric changes to paired IPv4 A and IPv6 AAAA DDNS functions"
name: "Generate Mirrored A and AAAA Changes"
argument-hint: "Describe the change to apply to both functions, plus any intentional differences"
agent: "agent"
---
Implement the requested change as a mirrored update across both DNS functions in this workspace.

Primary targets:
- [UpdateStargateIPv4Address/run.ps1](../../UpdateStargateIPv4Address/run.ps1)
- [UpdateStargateIPv6Address/run.ps1](../../UpdateStargateIPv6Address/run.ps1)

Also consider related files when needed:
- [UpdateStargateIPv4Address/function.json](../../UpdateStargateIPv4Address/function.json)
- [UpdateStargateIPv6Address/function.json](../../UpdateStargateIPv6Address/function.json)
- [.github/copilot-instructions.md](../copilot-instructions.md)

Requirements:
1. Keep behavior and structure aligned between A and AAAA flows.
2. Preserve intentional type-specific differences only:
   - RecordType A with Ipv4Address for IPv4
   - RecordType AAAA with Ipv6Address for IPv6
3. If one side cannot be mirrored exactly, explain why and document the intentional divergence in the final summary.
4. Keep changes minimal and avoid unrelated refactors.
5. Preserve existing function authorization level and request contract unless explicitly asked to change them.

Execution steps:
1. Briefly restate the requested change and identify impacted files.
2. Apply edits to both function paths in the same pass.
3. Validate changed files for syntax or diagnostics.
4. Return a concise result with:
   - files changed
   - mirrored logic applied
   - any intentional differences
   - follow-up suggestions (if any)
