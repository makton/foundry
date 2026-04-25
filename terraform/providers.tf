provider "azurerm" {
  subscription_id = var.subscription_id
  use_oidc        = var.use_oidc

  features {
    key_vault {
      purge_soft_delete_on_destroy               = false
      recover_soft_deleted_key_vaults            = true
      purge_soft_deleted_secrets_on_destroy      = false
      recover_soft_deleted_secrets               = true
      purge_soft_deleted_certificates_on_destroy = false
      recover_soft_deleted_certificates          = true
    }
    cognitive_account {
      purge_soft_delete_on_destroy = false
    }
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
    machine_learning {
      purge_soft_deleted_workspace_on_destroy = false
    }
  }
}

provider "azuread" {
  # Inherits the same OIDC / service-principal credentials as azurerm.
  # The SP must hold the Application.ReadWrite.All Microsoft Graph app role.
  use_oidc = var.use_oidc
}

provider "azapi" {
  subscription_id = var.subscription_id
  use_oidc        = var.use_oidc
}

provider "random" {}
