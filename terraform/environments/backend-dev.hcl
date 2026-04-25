# Local init: terraform init -backend-config=environments/backend-dev.hcl
resource_group_name  = "rg-tfstate-foundry"
storage_account_name = "sttfstatefoundry"
container_name       = "tfstate"
key                  = "foundry/dev/terraform.tfstate"
use_oidc             = false  # use az login locally
