locals {
  # Naming convention: {type}-{project}-{env}-{region}-{instance}
  name_prefix = "${var.project_name}-${var.environment}-${var.location_short}"

  resource_names = {
    resource_group       = "rg-${local.name_prefix}-${var.instance_number}"
    vnet                 = "vnet-${local.name_prefix}-${var.instance_number}"
    nsg_pe               = "nsg-pe-${local.name_prefix}-${var.instance_number}"
    nsg_agents           = "nsg-agents-${local.name_prefix}-${var.instance_number}"
    nsg_training         = "nsg-training-${local.name_prefix}-${var.instance_number}"
    log_analytics        = "log-${local.name_prefix}-${var.instance_number}"
    app_insights         = "appi-${local.name_prefix}-${var.instance_number}"
    key_vault            = "kv-${local.name_prefix}-${var.instance_number}"
    managed_identity     = "id-${local.name_prefix}-${var.instance_number}"
    storage_account      = "st${var.project_name}${var.environment}${var.instance_number}"
    openai               = "oai-${local.name_prefix}-${var.instance_number}"
    ai_search            = "srch-${local.name_prefix}-${var.instance_number}"
    container_registry   = "acr${var.project_name}${var.environment}${var.instance_number}"
    ai_hub               = "aih-${local.name_prefix}-${var.instance_number}"
  }

  # Private DNS zone names for all required PaaS services
  private_dns_zones = {
    blob             = "privatelink.blob.core.windows.net"
    file             = "privatelink.file.core.windows.net"
    queue            = "privatelink.queue.core.windows.net"
    table            = "privatelink.table.core.windows.net"
    dfs              = "privatelink.dfs.core.windows.net"
    key_vault        = "privatelink.vaultcore.azure.net"
    openai           = "privatelink.openai.azure.com"
    cognitive        = "privatelink.cognitiveservices.azure.com"
    search           = "privatelink.search.windows.net"
    acr              = "privatelink.azurecr.io"
    monitor          = "privatelink.monitor.azure.com"
    oms              = "privatelink.oms.opinsights.azure.com"
    ods              = "privatelink.ods.opinsights.azure.com"
    agent_svc        = "privatelink.agentsvc.azure-automation.net"
    cosmosdb         = "privatelink.documents.azure.com"
    function_app     = "privatelink.azurewebsites.net"
  }

  common_tags = merge(var.tags, {
    project     = var.project_name
    environment = var.environment
    location    = var.location
    managed_by  = "terraform"
  })
}
