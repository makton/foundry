variable "name" {
  description = "Name prefix used for app registration display names (e.g. foundry-dev-eus-001)"
  type        = string
}

variable "ui_redirect_uris" {
  description = "Allowed MSAL redirect URIs for the SPA login flow. Must include every hostname from which users access the app (e.g. https://chat.contoso.com). Add http://localhost:5173 for local dev."
  type        = list(string)
}
