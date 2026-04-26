# Function App VNet Content Routing

**Date:** 2026-04-26
**Status:** Approved

## Problem

The Azure Function App (`azurerm_linux_function_app`) in `terraform/modules/function_app/main.tf` has outbound VNet integration (`virtual_network_subnet_id`) and `vnet_route_all_enabled = true`, which routes all outbound IP traffic through the VNet. However, deployment package and content file downloads issued by the Functions host can still take an Azure-infrastructure path that bypasses the VNet integration. The `WEBSITE_CONTENTOVERVNET` app setting closes this gap.

## Change

Add one entry to `app_settings` in `azurerm_linux_function_app.main`:

```
WEBSITE_CONTENTOVERVNET = "1"
```

This instructs the Functions host to fetch its deployment package and content files through the VNet integration subnet rather than the Azure infrastructure bypass path.

## Scope

| File | Change |
|---|---|
| `terraform/modules/function_app/main.tf` | Add `WEBSITE_CONTENTOVERVNET = "1"` to `app_settings` |

No new resources. No variable additions. No module interface changes. No changes to CosmosDB, networking, or any other module.

## Out of Scope

- Removing `"AzureServices"` bypass from the backing storage (risk to scale controller — deferred)
- Azure Monitor private link scope for telemetry (separate effort)
- CosmosDB VNet filter / VNet rules (explicitly excluded)
