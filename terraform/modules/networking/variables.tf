variable "name" {
  description = "Name prefix for resources"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "instance_number" {
  description = "Instance number suffix"
  type        = string
}

variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
}

variable "private_endpoints_subnet_prefix" {
  description = "CIDR for private endpoints subnet"
  type        = string
}

variable "agents_subnet_prefix" {
  description = "CIDR for AI agents subnet"
  type        = string
}

variable "training_subnet_prefix" {
  description = "CIDR for ML training compute subnet"
  type        = string
}

variable "container_apps_subnet_prefix" {
  description = "CIDR for Container Apps Environment subnet (delegated to Microsoft.App/environments, min /27)"
  type        = string
}

variable "agw_subnet_prefix" {
  description = "CIDR for Application Gateway subnet (dedicated, no delegation, min /26 — /24 recommended)"
  type        = string
}

variable "function_app_subnet_prefix" {
  description = "CIDR for Function App VNet integration subnet (delegated to Microsoft.Web/serverFarms, min /26)"
  type        = string
}

variable "private_dns_zones" {
  description = "Map of DNS zone keys to zone names"
  type        = map(string)
}

variable "log_analytics_id" {
  description = "Log Analytics workspace resource ID for diagnostic settings"
  type        = string
}

variable "log_analytics_workspace_guid" {
  description = "Log Analytics workspace GUID (workspace_id property) — required for Traffic Analytics"
  type        = string
}

variable "log_analytics_workspace_location" {
  description = "Log Analytics workspace Azure region — required for Traffic Analytics"
  type        = string
}

variable "flow_log_retention_days" {
  description = "Days to retain raw VNet flow log blobs in storage before deletion (0 = retain forever)"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
