variable "name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "instance_number" {
  type = string
}

variable "account_tier" {
  type    = string
  default = "Standard"
}

variable "replication_type" {
  type    = string
  default = "ZRS"
}

variable "log_analytics_id" {
  type = string
}

variable "private_endpoint_subnet_id" {
  type = string
}

variable "private_dns_zone_ids" {
  description = "Map with keys: blob, file, queue, table, dfs"
  type        = map(string)
}

variable "cmk_key_versionless_id" {
  description = "Versionless Key Vault key ID for customer-managed encryption."
  type        = string
}

variable "cmk_key_id" {
  description = "ARM resource ID of the CMK key, used to scope the RBAC grant."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
