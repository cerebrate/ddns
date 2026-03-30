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

If these settings are not provided, the functions keep the original behavior and defaults.
