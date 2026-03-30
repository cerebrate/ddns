# Archived: Progressive Deployment (Slots)

This repository previously included active slot-based progressive deployment guidance and workflow.

Archived files:

- archive/workflows/progressive-deploy.yml

Summary of archived approach:

1. Validate and package.
2. Deploy to staging slot.
3. Run staging smoke tests.
4. Swap to production.
5. Run production smoke tests.
6. Swap back on failure.

This path is archived to avoid confusion while current external constraints require direct-to-production deployments.

If slot support becomes available again, restore and adapt the archived workflow and then update README accordingly.
