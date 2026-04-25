# ── Entra ID App Registrations ────────────────────────────────────────────────
#
# Two app registrations are created per environment:
#
#   chatbot-api  — the resource/API app that exposes the Chat.Read OAuth2 scope.
#                  chatbot-api validates Bearer tokens against this app's client ID.
#
#   chatbot-ui   — the SPA client that requests the Chat.Read scope on behalf of
#                  the signed-in user. Pre-authorized so users skip consent prompts.
#
# Prerequisites: the service principal running Terraform must hold the
#   Application.ReadWrite.All  Microsoft Graph role (app role, not delegated).
# Grant via: az ad app permission add / az role assignment create on the SP.

data "azurerm_client_config" "current" {}

resource "random_uuid" "api_scope_id" {}

# ── API app registration ───────────────────────────────────────────────────────

resource "azuread_application" "api" {
  display_name     = "${var.name}-api"
  sign_in_audience = "AzureADMyOrg"

  api {
    requested_access_token_version = 2

    oauth2_permission_scopes {
      id                         = random_uuid.api_scope_id.result
      value                      = "Chat.Read"
      type                       = "User"
      admin_consent_display_name = "Call Chatbot API"
      admin_consent_description  = "Allows the SPA to call the chatbot API on behalf of the signed-in user."
      user_consent_display_name  = "Call Chatbot API"
      user_consent_description   = "Allow this app to call the chatbot API on your behalf."
      enabled                    = true
    }
  }
}

# Application ID URI — required for the full scope string api://<client_id>/Chat.Read
resource "azuread_application_identifier_uri" "api" {
  application_id = azuread_application.api.id
  identifier_uri = "api://${azuread_application.api.client_id}"
}

resource "azuread_service_principal" "api" {
  client_id = azuread_application.api.client_id
}

# ── UI (SPA) app registration ──────────────────────────────────────────────────

resource "azuread_application" "ui" {
  display_name     = "${var.name}-ui"
  sign_in_audience = "AzureADMyOrg"

  single_page_application {
    redirect_uris = var.ui_redirect_uris
  }

  required_resource_access {
    resource_app_id = azuread_application.api.client_id

    resource_access {
      id   = random_uuid.api_scope_id.result
      type = "Scope"
    }
  }
}

resource "azuread_service_principal" "ui" {
  client_id = azuread_application.ui.client_id
}

# Pre-authorize the UI so users are not prompted for consent on every sign-in
resource "azuread_application_pre_authorized" "ui_to_api" {
  application_id       = azuread_application.api.id
  authorized_client_id = azuread_application.ui.client_id
  permission_ids       = [random_uuid.api_scope_id.result]
}
