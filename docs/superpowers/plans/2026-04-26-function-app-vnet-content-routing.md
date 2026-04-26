# Function App VNet Content Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Force the Azure Function App's content/package downloads through its VNet integration by adding `WEBSITE_CONTENTOVERVNET = "1"` to `app_settings`.

**Architecture:** Single app setting added to `azurerm_linux_function_app.main` in the function_app module. No new resources, variables, or module interface changes. The setting instructs the Functions host to use the VNet integration subnet for content fetches instead of the Azure infrastructure bypass path.

**Tech Stack:** Terraform / azurerm >= 4.0

---

### Task 1: Add `WEBSITE_CONTENTOVERVNET` to function app settings

**Files:**
- Modify: `terraform/modules/function_app/main.tf` (the `app_settings` map inside `azurerm_linux_function_app.main`)

- [ ] **Step 1: Open the file and locate the app_settings block**

  The block starts around line 109 with `app_settings = {`. Find the `# ── Monitoring ──` section near the bottom of the map, just before the closing `}`.

- [ ] **Step 2: Add the setting**

  Insert one line immediately after `APPLICATIONINSIGHTS_CONNECTION_STRING` and before the closing `}` of `app_settings`:

  ```hcl
      # ── VNet content routing ──
      WEBSITE_CONTENTOVERVNET = "1"
  ```

  The bottom of `app_settings` should now read:

  ```hcl
      # ── Monitoring ──
      APPLICATIONINSIGHTS_CONNECTION_STRING = var.application_insights_connection_string
      ApplicationInsightsAgent_EXTENSION_VERSION = "~3"

      # ── VNet content routing ──
      WEBSITE_CONTENTOVERVNET = "1"
    }
  ```

- [ ] **Step 3: Verify HCL syntax is valid**

  From the repo root, run:

  ```bash
  cd terraform && terraform fmt -check -recursive
  ```

  Expected: exits 0 with no output. If it exits non-zero, run `terraform fmt -recursive` to auto-fix whitespace, then re-check.

  If `terraform` is not installed locally, skip to Step 4 — the CI pipeline runs `fmt` and `validate` on every PR.

- [ ] **Step 4: Confirm the setting appears exactly once in the module**

  ```bash
  grep -n "WEBSITE_CONTENTOVERVNET" terraform/modules/function_app/main.tf
  ```

  Expected output (line number may differ):

  ```
  155:    WEBSITE_CONTENTOVERVNET = "1"
  ```

  Any other count (0 or >1) means the edit needs to be corrected.

- [ ] **Step 5: Commit**

  ```bash
  git add terraform/modules/function_app/main.tf
  git commit -m "feat(infra): force function app content fetches through VNet integration"
  ```
