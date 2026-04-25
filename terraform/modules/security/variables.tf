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

variable "tenant_id" {
  description = "Azure Active Directory tenant ID"
  type        = string
}

variable "key_vault_sku" {
  type    = string
  default = "standard"
}

variable "log_analytics_id" {
  type = string
}

variable "private_endpoint_subnet_id" {
  type = string
}

variable "private_dns_zone_key_vault" {
  description = "Resource ID of the Key Vault private DNS zone"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
