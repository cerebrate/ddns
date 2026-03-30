## Plan: Progressive Azure Hardening Rollout

Deployment-first sequence to reduce release risk: first modernize deploy/runtime plumbing, then land hardening changes behind automated tests, and only release through staged slot validation and swap.

Step-by-step

1. Phase 1, Deployment prerequisites first (blocking)
2. Upgrade extension bundle in host.json to the current Azure Functions v4-recommended range, then verify local startup with func host start.
3. Define production deployment topology: staging slot + production swap model, required approvals, and rollback owner/process.
4. Add infrastructure-as-code for required Azure resources and configuration:
   1. Function App runtime + staging slot
   2. System-assigned managed identity
   3. RBAC assignment scoped to DNS zone where possible (resource-group scope only if required)
   4. App settings and slot settings
5. Keep current defaults and formalize settings contract from code/docs:
   1. DDNS_RESOURCE_GROUP, DDNS_TTL
   2. Future hardening settings for allowlists and optional shared-secret check
   3. Update docs in README.md.
6. Add CI/CD with progressive deployment gates:
   1. Build/package
   2. Run tests
   3. Deploy to staging slot
   4. Smoke test
   5. Manual approval
   6. Slot swap
   7. Post-swap smoke and rollback trigger

7. Phase 2, Code hardening (released only via phase 1 pipeline)
8. Update both handlers to fail closed on non-NotFound DNS lookup errors instead of falling into create path:
   1. UpdateStargateIPv4Address/run.ps1
   2. UpdateStargateIPv6Address/run.ps1
9. Add request policy controls using app settings:
   1. Allowed zones
   2. Allowed record names
   3. Clear 400/403 responses for out-of-policy requests
10. Optionally add defense-in-depth auth (shared secret header/query) while retaining function-key compatibility for OpenWRT.
11. Improve operational telemetry and alerts in host.json:
   1. Capture enough request-level signal for abuse/debugging
   2. Alert on invalid request spikes, DNS write failures, and exception bursts

12. Phase 3, Automated test suite (parallel once interfaces stabilize)
13. Introduce Pester 5 test project and testable helper functions extracted from current handler flow.
14. Add unit tests for request parsing and normalization:
   1. Query/body fallback precedence
   2. Trim behavior
   3. Missing input handling
   4. DDNS_RESOURCE_GROUP and DDNS_TTL fallback behavior
15. Add unit tests for IP validation parity:
   1. IPv4 accepts only IPv4 in A handler
   2. IPv6 accepts only IPv6 in AAAA handler
   3. Malformed and whitespace-edge inputs
16. Add mocked DNS decision-path tests:
   1. No-op
   2. Update
   3. Create
   4. Lookup NotFound
   5. Lookup non-NotFound failure
   6. Set/New failures
17. Add response contract tests for both handlers to guarantee status/body consistency across branches.
18. Add end-to-end smoke tests using dedicated canary records for both A and AAAA updates.

19. Phase 4, Progressive release and operations
20. Deploy hardened build to staging slot only and run smoke tests against canary hostnames.
21. Swap to production only when tests and alerts are green; run post-swap smoke checks and bake-window monitoring.
22. If failure criteria trip, swap back immediately and open incident follow-up.
23. Establish recurring ops cadence:
   1. Function key rotation
   2. RBAC least-privilege review
   3. Dependency/version review for extension bundle and Az modules
   4. Rollback drill rehearsal

Relevant existing files

1. host.json
2. profile.ps1
3. requirements.psd1
4. README.md
5. UpdateStargateIPv4Address/run.ps1
6. UpdateStargateIPv6Address/run.ps1
7. UpdateStargateIPv4Address/function.json
8. UpdateStargateIPv6Address/function.json

Verification gates

1. Local: func host start succeeds after bundle update and handler changes.
2. Automated: full Pester suite passes in CI before any deployment.
3. Staging: canary smoke tests pass for both A and AAAA flows.
4. Release: swap gate requires approval + green tests.
5. Post-release: smoke tests pass and alerts remain below thresholds during bake window.
6. Resilience: rollback swap-back path validated and timed.
