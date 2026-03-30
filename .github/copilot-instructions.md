# Project Guidelines

## Scope
This repository contains two HTTP-triggered Azure Functions written in PowerShell for Dynamic DNS updates:
- UpdateStargateIPv4Address updates A records.
- UpdateStargateIPv6Address updates AAAA records.

Keep changes small and symmetric across both functions unless a difference is intentional and documented.

## Build And Run
Use these commands and workflows for local development:
- Start Functions host: func host start
- Preferred VS Code debug profile: Attach to PowerShell Functions
- There is no compile step; scripts execute directly.

Before local runs, ensure local settings and auth are configured:
- local.settings.json is required locally and is intentionally git-ignored.
- profile.ps1 uses managed identity auth. Local testing may require Azure CLI login instead.

## Architecture
Key files and boundaries:
- host.json: runtime, extension bundle, managed dependency, logging.
- requirements.psd1: Az.Accounts and Az.Dns dependencies.
- profile.ps1: Azure sign-in on cold start with Connect-AzAccount -Identity.
- UpdateStargateIPv4Address/run.ps1: A record logic.
- UpdateStargateIPv6Address/run.ps1: AAAA record logic.

Function contract for both endpoints:
- Inputs: Name, Zone, reqIP (from query string, then body fallback)
- Trigger: HTTP GET or POST with function-level authorization
- Output: 200 on update/no-op/create, 400 when required inputs are missing

## Conventions
Follow these project-specific conventions:
- Preserve function authLevel as function unless explicitly requested otherwise.
- Keep resource and DNS behavior explicit. ResourceGroupName and TTL are currently hardcoded in scripts.
- Keep IPv4 and IPv6 flows aligned: request parsing, lookup, compare, update/create, response.
- Prefer clear, operator-friendly logging with Write-Host for each major branch.
- When changing request shape or response text, update both functions consistently.

## Known Pitfalls
Watch for these existing issues and risks when editing:
- In both run.ps1 files, Zone fallback from body currently assigns to Name in one branch. Avoid copying this bug into new logic and fix carefully when touching parameter parsing.
- Input IP format is not validated today; malformed reqIP can pass through to DNS operations.
- Functions assume DNS records are in Resource Group Standard.

## Azure Deployment Notes
When preparing deployment-related changes, preserve these assumptions unless intentionally migrating:
- Function App runtime is Azure Functions v4 with PowerShell.
- Managed identity is expected and required for DNS updates.
- The Function App identity needs DNS Zone Contributor on the relevant zone/resource scope.
- HTTP callers (for example OpenWRT ddns-scripts) pass name, zone, and reqIP in the update URL.

## External References
Link to canonical docs and article context instead of duplicating long setup guides:
- README: ../README.md
- Article walkthrough: https://randombytes.substack.com/p/ddns-with-openwrt-and-azure
- Azure DNS overview: https://learn.microsoft.com/en-us/azure/dns/
- Azure Functions PowerShell local workflow: https://learn.microsoft.com/en-us/azure/azure-functions/create-first-function-vs-code-powershell
