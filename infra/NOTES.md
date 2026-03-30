# IaC Baseline — Planning Notes

Status: **Pinned / Pending decision**

## What this would cover

A small `infra/` Bicep baseline to bring the Azure-side configuration under version control. Four logical layers, in recommended implementation order:

### 1. App settings

Declare the four DDNS app settings as Bicep parameters applied to the existing Function App resource. Prevents configuration drift — the source of truth moves from the portal to the repo.

Settings to manage:
- `DDNS_RESOURCE_GROUP` (default: `Standard`)
- `DDNS_TTL` (default: `3600`)
- `DDNS_ALLOWED_ZONES` (comma-separated; required for allowlist enforcement)
- `DDNS_ALLOWED_RECORD_NAMES` (comma-separated; required for allowlist enforcement)

Pattern: use `existing` resource reference to the Function App, then `resource appSettings 'config'` to apply settings without redeploying the app itself.

### 2. Managed identity enforcement

Ensure the Function App's system-assigned managed identity is enabled in Bicep (`identity: { type: 'SystemAssigned' }`), so it cannot be accidentally disabled via the portal. Currently assumed present but not enforced in code.

### 3. RBAC — DNS Zone Contributor

Assign `DNS Zone Contributor` to the Function App identity, scoped to the specific DNS zone resource (not the whole resource group). Zone-scoped is preferred: principle of least privilege, and it prevents the identity from touching other record sets in the resource group if scope ever widens.

Role assignment resource references:
- Principal: Function App system-assigned identity `principalId`
- Role definition ID: `befefa01-2a29-4197-83a8-272ff33ce314` (DNS Zone Contributor)
- Scope: the DNS zone resource ID

### 4. Alert rules (optional)

App Insights / Azure Monitor alert rules for operational visibility:
- Function failure rate spike (exceptions or `exceptions | where ...` KQL)
- 403 spike on either function (unexpected allowlist mismatches)
- Backoff state: function disabled flag != false (detect if auto-backoff fired and wasn't cleared)

Requires an Action Group resource for notification routing (email/webhook). This layer is independent and can be added after the core three.

---

## Recommended Bicep structure

```
infra/
  main.bicep          # orchestrates modules, accepts top-level params
  modules/
    appsettings.bicep # app settings on the existing Function App
    identity.bicep    # managed identity enforcement
    rbac.bicep        # DNS Zone Contributor role assignment
    alerts.bicep      # (optional) alert rules + action group
  parameters/
    production.bicepparam  # production parameter values
```

Parameters needed across modules:
- `functionAppName` — name of the existing Function App
- `functionAppResourceGroup` — RG containing the Function App
- `dnsZoneResourceId` — full resource ID of the DNS zone
- `ddnsAllowedZones` — value to write to app setting
- `ddnsAllowedRecordNames` — value to write to app setting
- `ddnsResourceGroup` — value for `DDNS_RESOURCE_GROUP` app setting
- `ddnsTtl` — value for `DDNS_TTL` app setting (string)

---

## Key decisions still open

1. **Which resource group hosts the Function App?** The Bicep deployment command (`az deployment group create`) needs a target RG. If the Function App and DNS zone are in different RGs, the role assignment module needs to deploy at subscription scope or use a nested deployment.

2. **Deployment integration**: Should `az deployment group create` (or `bicep build` + ARM deploy) be added as a step in `direct-production-deploy.yml`, or run manually as a separate infra-change workflow? Infra changes are lower frequency than code deploys, so a separate `deploy-infra.yml` workflow may be cleaner.

3. **Alert routing**: What Action Group target — email, Teams webhook, PagerDuty? Needed before `alerts.bicep` can be parameterized.

4. **Scope of migration**: Does the Function App itself get imported into Bicep state, or only the settings/RBAC are managed and the app resource stays portal-created? The `existing` keyword approach avoids importing the app, which is lower risk for an existing live service.

---

## Recommended next step when ready

Start with the smallest, safest layer: `appsettings.bicep` using `existing` resource references. This has no blast radius (it only writes config values, does not redeploy the app), and it immediately eliminates the risk of config drift on `DDNS_ALLOWED_ZONES` and `DDNS_ALLOWED_RECORD_NAMES`.

Then add `identity.bicep` and `rbac.bicep` together (they are coupled — the identity `principalId` feeds the role assignment).

Defer alert rules until the three core layers are working and the Action Group target is decided.
