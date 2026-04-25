# ── Network Security Groups ───────────────────────────────────────────────────

resource "azurerm_network_security_group" "private_endpoints" {
  name                = "nsg-pe-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_network_security_group" "agents" {
  name                = "nsg-agents-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_network_security_rule" "agents_deny_all_inbound" {
  name                        = "Deny-All-Inbound"
  priority                    = 4096
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.agents.name
}

resource "azurerm_network_security_group" "training" {
  name                = "nsg-training-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_network_security_rule" "training_deny_all_inbound" {
  name                        = "Deny-All-Inbound"
  priority                    = 4096
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.training.name
}

# Allow inbound from VNet, deny all other inbound for private endpoints
resource "azurerm_network_security_rule" "pe_allow_vnet_inbound" {
  name                        = "Allow-VNet-Inbound"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "VirtualNetwork"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.private_endpoints.name
}

resource "azurerm_network_security_rule" "pe_deny_all_inbound" {
  name                        = "Deny-All-Inbound"
  priority                    = 4096
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.private_endpoints.name
}

# ── Virtual Network & Subnets ─────────────────────────────────────────────────

resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.vnet_address_space
  tags                = var.tags
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-private-endpoints"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.private_endpoints_subnet_prefix]

  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_subnet_network_security_group_association" "private_endpoints" {
  subnet_id                 = azurerm_subnet.private_endpoints.id
  network_security_group_id = azurerm_network_security_group.private_endpoints.id
}

# Agent subnet — delegated to Microsoft.App/environments for AI Foundry Agent Service
resource "azurerm_subnet" "agents" {
  name                 = "snet-agents"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.agents_subnet_prefix]

  delegation {
    name = "delegation-app-environments"
    service_delegation {
      name = "Microsoft.App/environments"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "agents" {
  subnet_id                 = azurerm_subnet.agents.id
  network_security_group_id = azurerm_network_security_group.agents.id
}

# Container Apps subnet — dedicated delegation for API platform workloads
resource "azurerm_network_security_group" "container_apps" {
  name                = "nsg-cae-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Allow HTTPS ingress from VNet to Container Apps
resource "azurerm_network_security_rule" "cae_allow_https_inbound" {
  name                        = "Allow-HTTPS-VNet-Inbound"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.container_apps.name
}

# Required for Container Apps managed cert challenges
resource "azurerm_network_security_rule" "cae_allow_http_inbound" {
  name                        = "Allow-HTTP-VNet-Inbound"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.container_apps.name
}

# Defense-in-depth: explicitly block internet ingress to the CAE subnet.
# internal_load_balancer_enabled = true removes the public endpoint, but this rule
# makes the intent unambiguous and catches any misconfiguration at the network layer.
resource "azurerm_network_security_rule" "cae_deny_internet_inbound" {
  name                        = "Deny-Internet-Inbound"
  priority                    = 4096
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "Internet"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.container_apps.name
}

resource "azurerm_subnet" "container_apps" {
  name                 = "snet-container-apps"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.container_apps_subnet_prefix]

  delegation {
    name = "delegation-app-environments"
    service_delegation {
      name = "Microsoft.App/environments"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "container_apps" {
  subnet_id                 = azurerm_subnet.container_apps.id
  network_security_group_id = azurerm_network_security_group.container_apps.id
}

# Application Gateway subnet — dedicated, no delegation, requires specific NSG rules
resource "azurerm_network_security_group" "agw" {
  name                = "nsg-agw-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Azure REQUIRES this rule — AGW infrastructure probes use ports 65200-65535
resource "azurerm_network_security_rule" "agw_gateway_manager" {
  name                        = "Allow-GatewayManager-Inbound"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "65200-65535"
  source_address_prefix       = "GatewayManager"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.agw.name
}

# Azure REQUIRES this rule — health probes from internal Azure LB
resource "azurerm_network_security_rule" "agw_azure_lb" {
  name                        = "Allow-AzureLoadBalancer-Inbound"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "AzureLoadBalancer"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.agw.name
}

resource "azurerm_network_security_rule" "agw_https_inbound" {
  name                        = "Allow-HTTPS-Internet-Inbound"
  priority                    = 200
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "Internet"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.agw.name
}

resource "azurerm_network_security_rule" "agw_http_inbound" {
  name                        = "Allow-HTTP-Internet-Inbound"
  priority                    = 210
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = "Internet"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.agw.name
}

resource "azurerm_network_security_rule" "agw_vnet_outbound" {
  name                        = "Allow-VNet-Outbound"
  priority                    = 100
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "VirtualNetwork"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.agw.name
}

resource "azurerm_network_security_rule" "agw_deny_all_outbound" {
  name                        = "Deny-All-Outbound"
  priority                    = 4096
  direction                   = "Outbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "Internet"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.agw.name
}

resource "azurerm_subnet" "agw" {
  name                 = "snet-agw"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.agw_subnet_prefix]
  # No delegation — AGW manages its own resources within this subnet
}

resource "azurerm_subnet_network_security_group_association" "agw" {
  subnet_id                 = azurerm_subnet.agw.id
  network_security_group_id = azurerm_network_security_group.agw.id
}

# Function App VNet integration subnet — outbound traffic from Function App flows here
# Service endpoints allow the Function App to reach scoped storage and CosmosDB without public IPs
resource "azurerm_network_security_group" "function_app" {
  name                = "nsg-func-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_network_security_rule" "func_allow_vnet_outbound" {
  name                        = "Allow-VNet-Outbound"
  priority                    = 100
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "VirtualNetwork"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.function_app.name
}

# Allow HTTPS to Azure PaaS service tags (private endpoints resolve to VNet IPs,
# but service tags cover the management plane calls the Functions host makes)
resource "azurerm_network_security_rule" "func_allow_azure_outbound" {
  name                        = "Allow-AzureCloud-HTTPS-Outbound"
  priority                    = 110
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "*"
  destination_address_prefix  = "AzureCloud"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.function_app.name
}

resource "azurerm_network_security_rule" "func_deny_all_outbound" {
  name                        = "Deny-All-Outbound"
  priority                    = 4096
  direction                   = "Outbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.function_app.name
}

resource "azurerm_subnet" "function_app" {
  name                 = "snet-function-app"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.function_app_subnet_prefix]

  # Service endpoints so the Function App can reach scoped PaaS resources
  service_endpoints = [
    "Microsoft.Storage",
    "Microsoft.CosmosDB",
    "Microsoft.KeyVault",
  ]

  delegation {
    name = "delegation-web-serverfarms"
    service_delegation {
      name = "Microsoft.Web/serverFarms"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action",
      ]
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "function_app" {
  subnet_id                 = azurerm_subnet.function_app.id
  network_security_group_id = azurerm_network_security_group.function_app.id
}

# Training subnet for ML compute clusters and instances
resource "azurerm_subnet" "training" {
  name                 = "snet-training"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.training_subnet_prefix]
}

resource "azurerm_subnet_network_security_group_association" "training" {
  subnet_id                 = azurerm_subnet.training.id
  network_security_group_id = azurerm_network_security_group.training.id
}

# ── Private DNS Zones ─────────────────────────────────────────────────────────

resource "azurerm_private_dns_zone" "zones" {
  for_each = var.private_dns_zones

  name                = each.value
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "zones" {
  for_each = var.private_dns_zones

  name                  = "link-${each.key}-${var.name}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.zones[each.key].name
  virtual_network_id    = azurerm_virtual_network.main.id
  registration_enabled  = false
  tags                  = var.tags
}

# ── VNet Flow Logs ────────────────────────────────────────────────────────────
# VNet-level flow logging captures all traffic crossing the VNet in a single
# resource (vs. one flow log per NSG). Traffic Analytics aggregates the raw
# blobs every 10 minutes and ships them to Log Analytics.

locals {
  flow_log_storage_name = substr(replace("stflow${var.name}${var.instance_number}", "-", ""), 0, 24)

  nsgs = {
    "pe"       = azurerm_network_security_group.private_endpoints.id
    "agents"   = azurerm_network_security_group.agents.id
    "training" = azurerm_network_security_group.training.id
    "cae"      = azurerm_network_security_group.container_apps.id
    "agw"      = azurerm_network_security_group.agw.id
    "func"     = azurerm_network_security_group.function_app.id
  }
}

data "azurerm_network_watcher" "main" {
  name                = "NetworkWatcher_${var.location}"
  resource_group_name = "NetworkWatcherRG"
}

# Dedicated storage account — Network Watcher writes raw flow blobs here;
# AzureServices bypass is required for the watcher to reach the account.
resource "azurerm_storage_account" "flow_logs" {
  name                     = local.flow_log_storage_name
  location                 = var.location
  resource_group_name      = var.resource_group_name
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"

  public_network_access_enabled = true
  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  tags = var.tags
}

resource "azurerm_network_watcher_flow_log" "vnet" {
  network_watcher_name = data.azurerm_network_watcher.main.name
  resource_group_name  = data.azurerm_network_watcher.main.resource_group_name
  name                 = "fl-vnet-${var.name}-${var.instance_number}"

  target_resource_id = azurerm_virtual_network.main.id
  storage_account_id = azurerm_storage_account.flow_logs.id
  enabled            = true
  version            = 2

  retention_policy {
    enabled = true
    days    = var.flow_log_retention_days
  }

  traffic_analytics {
    enabled               = true
    workspace_id          = var.log_analytics_workspace_guid
    workspace_region      = var.log_analytics_workspace_location
    workspace_resource_id = var.log_analytics_id
    interval_in_minutes   = 10
  }

  tags = var.tags
}

# ── Diagnostic Settings ───────────────────────────────────────────────────────

resource "azurerm_monitor_diagnostic_setting" "vnet" {
  name                       = "diag-vnet-${var.name}"
  target_resource_id         = azurerm_virtual_network.main.id
  log_analytics_workspace_id = var.log_analytics_id

  enabled_log {
    category = "VMProtectionAlerts"
  }

  metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "nsgs" {
  for_each = local.nsgs

  name                       = "diag-nsg-${each.key}-${var.name}"
  target_resource_id         = each.value
  log_analytics_workspace_id = var.log_analytics_id

  enabled_log {
    category = "NetworkSecurityGroupEvent"
  }

  enabled_log {
    category = "NetworkSecurityGroupRuleCounter"
  }
}
