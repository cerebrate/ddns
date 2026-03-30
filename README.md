# ddns

My Dynamic DNS functions for Azure.

(For details, please see my article at https://randombytes.substack.com/p/ddns-with-openwrt-and-azure .)

## App settings

The functions support these optional app settings:

- `DDNS_RESOURCE_GROUP`: Resource group containing the DNS zone.
	- Default: `Standard`
- `DDNS_TTL`: TTL (seconds) used when creating new DNS records.
	- Default: `3600`
	- Validation: must be a positive integer; invalid values fall back to `3600`.
- `DDNS_ALLOWED_ZONES`: Comma-separated exact-match allowlist of permitted DNS zones.
	- Optional: if unset or empty, zones are unrestricted.
	- Matching: case-insensitive after trimming.
- `DDNS_ALLOWED_RECORD_NAMES`: Comma-separated exact-match allowlist of permitted record names.
	- Optional: if unset or empty, record names are unrestricted.
	- Matching: case-insensitive after trimming.

If these settings are not provided, the functions keep the original behavior and defaults.

## Direct-to-production workflow (no slots)

If you cannot use deployment slots or a separate staging Function App, use:

- [.github/workflows/direct-production-deploy.yml](.github/workflows/direct-production-deploy.yml)
- [.github/workflows/re-enable-functions.yml](.github/workflows/re-enable-functions.yml) for one-click recovery after backoff

Flow:

1. Validate PowerShell syntax.
2. Run Pester tests.
3. Generate deployment metadata artifact.
4. Package function app content.
5. Deploy directly to production.
6. Run production smoke tests for IPv4 and IPv6.
7. If smoke tests fail, automatically back off by disabling both functions:
	- `AzureWebJobs.UpdateStargateIPv4Address.Disabled=true`
	- `AzureWebJobs.UpdateStargateIPv6Address.Disabled=true`
8. Emit a GitHub workflow error and step summary.
9. Upload an incident report artifact for operators.

This does not roll back code. It prevents further update traffic until you investigate and re-enable.

The workflow retains these artifacts for 30 days:

1. Deployment package
2. Deployment metadata (`deployment-metadata.json`)
3. Backoff incident report (only when smoke fails)

### Required GitHub variables for direct workflow

- `AZURE_RESOURCE_GROUP`
- `AZURE_FUNCTIONAPP_NAME`
- `SMOKE_ZONE`
- `SMOKE_IPV4_RECORD`
- `SMOKE_IPV6_RECORD`
- `SMOKE_IPV4_ADDRESS`
- `SMOKE_IPV6_ADDRESS`

### Required GitHub secrets for direct workflow

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `PROD_IPV4_FUNCTION_URL`
- `PROD_IPV6_FUNCTION_URL`

### Azure-side requirements for direct workflow

1. Ensure managed identity and DNS role assignment are already configured for the Function App.
2. Ensure the GitHub OIDC principal has permissions to:
	- Deploy zip package to the Function App
	- Update app settings (needed for automatic backoff)
3. Configure GitHub `production` environment with required reviewers/approval.

### Re-enable functions after backoff

After fixing the issue, either:

1. Run [.github/workflows/re-enable-functions.yml](.github/workflows/re-enable-functions.yml), or
2. Re-enable both functions manually:

```bash
az functionapp config appsettings set \
  --resource-group <resource-group> \
  --name <function-app-name> \
  --settings \
	 AzureWebJobs.UpdateStargateIPv4Address.Disabled=false \
	 AzureWebJobs.UpdateStargateIPv6Address.Disabled=false
```

## Operator runbook (direct production mode)

### 1. Deploy

1. Confirm production environment approvals are in place on GitHub.
2. Run workflow: [.github/workflows/direct-production-deploy.yml](.github/workflows/direct-production-deploy.yml).
3. Wait for jobs to complete in order:
	- `validate_and_package`
	- `deploy_to_production`
	- `smoke_test_production`

### 2. Interpret smoke test outcomes

1. If `smoke_test_production` is green:
	- Deployment is considered successful.
	- No further action required.
2. If `smoke_test_production` fails and `backoff_on_smoke_failure` succeeds:
	- Both functions were automatically disabled.
	- Incoming DDNS updates are paused by design.
	- The workflow emits an error annotation and a step summary entry.
	- Download the retained `production-backoff-incident-report` artifact for the run record.
3. If both smoke and backoff jobs fail:
	- Assume deployment is unhealthy and functions may still be active.
	- Manually disable functions immediately (command below), then investigate.

Manual disable command:

```bash
az functionapp config appsettings set \
  --resource-group <resource-group> \
  --name <function-app-name> \
  --settings \
	 AzureWebJobs.UpdateStargateIPv4Address.Disabled=true \
	 AzureWebJobs.UpdateStargateIPv6Address.Disabled=true
```

### 3. Recover and re-enable

1. Investigate deployment and runtime logs in Azure.
2. Fix the issue in code/config and redeploy.
3. Re-enable functions using either:
	- Workflow: [.github/workflows/re-enable-functions.yml](.github/workflows/re-enable-functions.yml)
	- Manual CLI command in the Re-enable functions after backoff section.
4. Run a manual smoke verification by calling both production function URLs with known canary values.

### 4. Recommended checks after recovery

1. Confirm both Disabled flags are `false`.
2. Confirm both smoke calls return HTTP 200 and expected body text.
3. Confirm DNS records for canary names reflect expected values.
4. Record incident notes with root cause and mitigation applied.

## Archived workflows and docs

To avoid confusion under current constraints, the slot-based progressive deployment assets are archived:

- [archive/workflows/progressive-deploy.yml](archive/workflows/progressive-deploy.yml)
- [archive/docs/progressive-deployment.md](archive/docs/progressive-deployment.md)

## Automated tests (Pester)

This repository includes a baseline Pester suite under [tests](tests):

- [tests/DdnsFunctions.Tests.ps1](tests/DdnsFunctions.Tests.ps1)
- [tests/TestHelpers.ps1](tests/TestHelpers.ps1)

Current coverage focuses on handler contract behavior for both IPv4 and IPv6 functions:

1. Missing required input returns HTTP 400.
2. Query/body fallback (including reqIP body fallback) and trim behavior.
3. IP family validation (IPv4 only for A, IPv6 only for AAAA).
4. Zone allowlist enforcement returns HTTP 403 before any DNS call.
5. Record name allowlist enforcement returns HTTP 403 before any DNS call.
6. Zone and record name in allowlist — request proceeds.
7. Update path when current record differs.
8. No-op path when requested IP matches existing record (returns 200, no write).
9. Create path when no record exists.
10. DNS lookup failure returns HTTP 500 and does not fall through to create.
11. Default `DDNS_RESOURCE_GROUP` and `DDNS_TTL` behavior when app settings are absent.
12. Valid app-setting override behavior for resource group and TTL.
13. Invalid `DDNS_TTL` fallback to the default value.

Run locally:

```powershell
Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck
Invoke-Pester -Path ./tests
```

The direct production workflow also runs this suite before packaging and deployment.
