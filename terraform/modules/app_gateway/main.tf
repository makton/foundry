locals {
  # Separate backends that have explicit path prefixes from the default (catch-all) one
  routed_backends = { for k, v in var.backends : k => v if length(v.path_prefixes) > 0 }

  # AGW uses http/https based on whether a cert is configured
  https_enabled      = var.ssl_certificate_key_vault_secret_id != null
  main_listener_name = local.https_enabled ? "listener-https" : "listener-http"
  ssl_cert_name      = "ssl-cert-${var.name}"

  # Private listener — enabled when agw_private_ip is set.
  # The hostname (e.g. "api.foundry.internal") is split into a DNS zone
  # ("foundry.internal") and an A-record name ("api") for the private DNS zone.
  private_enabled         = var.agw_private_ip != null
  _hostname_parts         = local.private_enabled ? split(".", var.agw_private_hostname) : []
  private_dns_zone_name   = local.private_enabled ? join(".", slice(local._hostname_parts, 1, length(local._hostname_parts))) : null
  private_dns_record_name = local.private_enabled ? local._hostname_parts[0] : null
}

# ── Managed Identity ──────────────────────────────────────────────────────────
# Required for AGW to pull SSL certificates from Key Vault.

resource "azurerm_user_assigned_identity" "agw" {
  name                = "id-agw-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "agw_kv_secrets_user" {
  count = var.key_vault_id != null ? 1 : 0

  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.agw.principal_id
}

resource "azurerm_role_assignment" "agw_kv_certs_user" {
  count = var.key_vault_id != null ? 1 : 0

  scope                = var.key_vault_id
  role_definition_name = "Key Vault Certificate User"
  principal_id         = azurerm_user_assigned_identity.agw.principal_id
}

# ── Public IP ─────────────────────────────────────────────────────────────────

resource "azurerm_public_ip" "agw" {
  name                = "pip-agw-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.zones
  tags                = var.tags
}

# ── WAF Policies ──────────────────────────────────────────────────────────────
#
# Two policies are required:
#   main    — public listener; includes per-IP rate-limit custom rules
#   private — internal listener (nginx → chatbot-api); OWASP only, no rate limits
#
# Rate limits are intentionally absent from the private policy because the
# SocketAddr visible there is nginx's container IP, not the real client IP.
# Applying rate limits by SocketAddr on that listener would throttle all users
# once a single nginx replica exceeds the threshold.

resource "azurerm_web_application_firewall_policy" "main" {
  name                = "wafpol-agw-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  policy_settings {
    enabled                     = true
    mode                        = var.waf_mode
    request_body_check          = true
    max_request_body_size_in_kb = 128
    file_upload_limit_in_mb     = 100
  }

  
  # ── Rate-limit custom rules (per client IP, public listener only) ───────────
  #
  # Rule 10 — /api/chat (strict): protects the streaming chat endpoint.
  #   Fires after the internet-block rule (priority 1). When triggered it blocks;
  #   rule 20 is never reached. Limits a client to waf_rate_limit_chat_rpm req/min.
  #
  # Rule 20 — /api/ (broad): covers any other API endpoint (URL management, etc.).
  #   Only evaluated when rule 10 passes (within the chat quota or non-chat path).
  #   Limits a client to waf_rate_limit_api_rpm requests/min across all /api/ calls.
  #
  # Both rules group by SocketAddr (real client IP at the AGW edge).

  custom_rules {
    name               = "RateLimitChatPerIP"
    priority           = 10
    rule_type          = "RateLimitRule"
    rate_limit_duration  = "OneMin"
    rate_limit_threshold = var.waf_rate_limit_chat_rpm
    action             = "Block"

    group_by_user_session {
      group_by_variables {
        variable_name = "SocketAddr"
      }
    }

    match_conditions {
      match_variables {
        variable_name = "RequestUri"
      }
      operator           = "BeginsWith"
      negation_condition = false
      match_values       = ["/api/chat"]
    }
  }

  custom_rules {
    name               = "RateLimitApiPerIP"
    priority           = 20
    rule_type          = "RateLimitRule"
    rate_limit_duration  = "OneMin"
    rate_limit_threshold = var.waf_rate_limit_api_rpm
    action             = "Block"

    group_by_user_session {
      group_by_variables {
        variable_name = "SocketAddr"
      }
    }

    match_conditions {
      match_variables {
        variable_name = "RequestUri"
      }
      operator           = "BeginsWith"
      negation_condition = false
      match_values       = ["/api/"]
    }
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = var.waf_owasp_version
    }
    managed_rule_set {
      type    = "Microsoft_BotManagerRuleSet"
      version = "1.1"
    }
  }
}

# Internal WAF policy: OWASP + BotManager only — no IP-based rate limiting.
# Applied to the private listener so the chatbot-api gets OWASP coverage
# without the rate limit rules that would misfire on nginx's container IP.
resource "azurerm_web_application_firewall_policy" "private" {
  count = local.private_enabled ? 1 : 0

  name                = "wafpol-agw-int-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  policy_settings {
    enabled                     = true
    mode                        = var.waf_mode
    request_body_check          = true
    max_request_body_size_in_kb = 128
    file_upload_limit_in_mb     = 100
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = var.waf_owasp_version
    }
    managed_rule_set {
      type    = "Microsoft_BotManagerRuleSet"
      version = "1.1"
    }
  }
}

# ── Application Gateway ───────────────────────────────────────────────────────

resource "azurerm_application_gateway" "main" {
  name                = "agw-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  firewall_policy_id  = azurerm_web_application_firewall_policy.main.id
  tags                = var.tags

  sku {
    name = "WAF_v2"
    tier = "WAF_v2"
  }

  autoscale_configuration {
    min_capacity = var.autoscale_min_capacity
    max_capacity = var.autoscale_max_capacity
  }

  zones = var.zones

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.agw.id]
  }

  # ── Network ────────────────────────────────────────────────────────────────

  gateway_ip_configuration {
    name      = "gateway-ip-config"
    subnet_id = var.agw_subnet_id
  }

  frontend_ip_configuration {
    name                 = "frontend-public"
    public_ip_address_id = azurerm_public_ip.agw.id
  }

  # Private frontend — static IP within the AGW subnet.
  # nginx in chatbot-ui resolves api.foundry.internal (private DNS) to this IP
  # and proxies /api/ requests here. chatbot-api is not reachable from the public internet.
  dynamic "frontend_ip_configuration" {
    for_each = local.private_enabled ? [1] : []
    content {
      name                          = "frontend-private"
      subnet_id                     = var.agw_subnet_id
      private_ip_address            = var.agw_private_ip
      private_ip_address_allocation = "Static"
    }
  }

  frontend_port {
    name = "port-80"
    port = 80
  }

  frontend_port {
    name = "port-443"
    port = 443
  }

  # ── SSL Certificate ────────────────────────────────────────────────────────

  dynamic "ssl_certificate" {
    for_each = local.https_enabled ? [1] : []
    content {
      name                = local.ssl_cert_name
      key_vault_secret_id = var.ssl_certificate_key_vault_secret_id
    }
  }

  ssl_policy {
    policy_type          = "Predefined"
    policy_name          = "AppGwSslPolicy20220101"  # TLS 1.2+ only
  }

  # ── Backend Pools — one per Container App ─────────────────────────────────

  dynamic "backend_address_pool" {
    for_each = var.backends
    content {
      name  = "backend-${backend_address_pool.key}"
      fqdns = [backend_address_pool.value.fqdn]
    }
  }

  # ── HTTP Settings — use backend hostname so TLS cert matches ───────────────

  dynamic "backend_http_settings" {
    for_each = var.backends
    content {
      name                                = "http-settings-${backend_http_settings.key}"
      cookie_based_affinity               = "Disabled"
      port                                = backend_http_settings.value.backend_port
      protocol                            = backend_http_settings.value.backend_protocol
      request_timeout                     = 60
      pick_host_name_from_backend_address = true
      probe_name                          = "probe-${backend_http_settings.key}"
    }
  }

  # ── Health Probes ──────────────────────────────────────────────────────────

  dynamic "probe" {
    for_each = var.backends
    content {
      name                                      = "probe-${probe.key}"
      protocol                                  = probe.value.backend_protocol
      path                                      = probe.value.health_probe_path
      interval                                  = 30
      timeout                                   = 30
      unhealthy_threshold                       = 3
      pick_host_name_from_backend_http_settings = true

      match {
        status_code = ["200-399"]
      }
    }
  }

  # ── Listeners ──────────────────────────────────────────────────────────────

  # Public HTTP listener — redirects to HTTPS when cert configured, else routes directly.
  # host_name restricts the listener to a specific domain (null = any hostname).
  http_listener {
    name                           = "listener-http"
    frontend_ip_configuration_name = "frontend-public"
    frontend_port_name             = "port-80"
    protocol                       = "Http"
    host_name                      = var.custom_hostname
    firewall_policy_id             = azurerm_web_application_firewall_policy.main.id
  }

  # Private HTTP listener — bound to the AGW's internal IP only.
  # Responds exclusively to requests from within the VNet that present the
  # private hostname (agw_private_hostname) in the Host header, as nginx does.
  # Uses the private WAF policy (no IP rate limiting — nginx IP, not client IP).
  dynamic "http_listener" {
    for_each = local.private_enabled ? [1] : []
    content {
      name                           = "listener-private"
      frontend_ip_configuration_name = "frontend-private"
      frontend_port_name             = "port-80"
      protocol                       = "Http"
      host_name                      = var.agw_private_hostname
      firewall_policy_id             = azurerm_web_application_firewall_policy.private[0].id
    }
  }

  dynamic "http_listener" {
    for_each = local.https_enabled ? [1] : []
    content {
      name                           = "listener-https"
      frontend_ip_configuration_name = "frontend-public"
      frontend_port_name             = "port-443"
      protocol                       = "Https"
      ssl_certificate_name           = local.ssl_cert_name
      host_name                      = var.custom_hostname
      firewall_policy_id             = azurerm_web_application_firewall_policy.main.id
    }
  }

  # ── HTTP → HTTPS redirect ──────────────────────────────────────────────────

  dynamic "redirect_configuration" {
    for_each = local.https_enabled ? [1] : []
    content {
      name                 = "redirect-http-to-https"
      redirect_type        = "Permanent"
      target_listener_name = "listener-https"
      include_path         = true
      include_query_string = true
    }
  }

  dynamic "request_routing_rule" {
    for_each = local.https_enabled ? [1] : []
    content {
      name                        = "rule-redirect-http"
      rule_type                   = "Basic"
      priority                    = 10
      http_listener_name          = "listener-http"
      redirect_configuration_name = "redirect-http-to-https"
    }
  }

  # ── Path-based routing ─────────────────────────────────────────────────────
  # Routes /path-prefix/* to the matching Container App backend.
  # When all backends have empty path_prefixes (chatbot-api is private-listener-only),
  # the url_path_map is omitted and the routing rule degrades gracefully to Basic.

  dynamic "url_path_map" {
    for_each = length(local.routed_backends) > 0 ? [1] : []
    content {
      name                               = "pathmap-apis"
      default_backend_address_pool_name  = "backend-${var.default_backend_key}"
      default_backend_http_settings_name = "http-settings-${var.default_backend_key}"

      dynamic "path_rule" {
        for_each = local.routed_backends
        content {
          name                       = "path-${path_rule.key}"
          paths                      = path_rule.value.path_prefixes
          backend_address_pool_name  = "backend-${path_rule.key}"
          backend_http_settings_name = "http-settings-${path_rule.key}"
          firewall_policy_id         = azurerm_web_application_firewall_policy.main.id
        }
      }
    }
  }

  # Public listener routing rule.
  # PathBasedRouting when backends declare path prefixes; Basic (chatbot-ui only)
  # when chatbot-api has been moved to the private listener.
  request_routing_rule {
    name                       = "rule-apis"
    rule_type                  = length(local.routed_backends) > 0 ? "PathBasedRouting" : "Basic"
    priority                   = local.https_enabled ? 20 : 10
    http_listener_name         = local.main_listener_name
    url_path_map_name          = length(local.routed_backends) > 0 ? "pathmap-apis" : null
    backend_address_pool_name  = length(local.routed_backends) > 0 ? null : "backend-${var.default_backend_key}"
    backend_http_settings_name = length(local.routed_backends) > 0 ? null : "http-settings-${var.default_backend_key}"
  }

  # Private listener routing rule — direct Basic route to the API backend.
  # Priority 100 keeps it clearly separated from public rules (10, 20).
  dynamic "request_routing_rule" {
    for_each = local.private_enabled ? [1] : []
    content {
      name                       = "rule-private-api"
      rule_type                  = "Basic"
      priority                   = 100
      http_listener_name         = "listener-private"
      backend_address_pool_name  = "backend-${var.agw_private_backend_key}"
      backend_http_settings_name = "http-settings-${var.agw_private_backend_key}"
    }
  }

  depends_on = [
    azurerm_role_assignment.agw_kv_secrets_user,
    azurerm_role_assignment.agw_kv_certs_user,
  ]
}

# ── Private DNS zone for internal AGW listener ────────────────────────────────
# Resolves agw_private_hostname (e.g. api.foundry.internal) to the AGW private IP
# for all resources in the linked VNet. nginx in chatbot-ui relies on this.

resource "azurerm_private_dns_zone" "agw_internal" {
  count = local.private_enabled ? 1 : 0

  name                = local.private_dns_zone_name
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "agw_internal" {
  count = local.private_enabled ? 1 : 0

  name                  = "link-agw-internal-${var.name}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.agw_internal[0].name
  virtual_network_id    = var.vnet_id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_a_record" "agw_private" {
  count = local.private_enabled ? 1 : 0

  name                = local.private_dns_record_name
  zone_name           = azurerm_private_dns_zone.agw_internal[0].name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [var.agw_private_ip]
}

# ── Diagnostic Settings ───────────────────────────────────────────────────────

resource "azurerm_monitor_diagnostic_setting" "agw" {
  name                       = "diag-agw-${var.name}"
  target_resource_id         = azurerm_application_gateway.main.id
  log_analytics_workspace_id = var.log_analytics_id

  enabled_log {
    category = "ApplicationGatewayAccessLog"
  }
  enabled_log {
    category = "ApplicationGatewayPerformanceLog"
  }
  enabled_log {
    category = "ApplicationGatewayFirewallLog"
  }

  metric {
    category = "AllMetrics"
  }
}
