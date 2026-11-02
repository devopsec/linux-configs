# Azure Functions — plans, Python apps, triggers, deployment


## Contents
- Runtime and plan choice (2026)
- Tooling (no piped installers)
- Create app (Flex Consumption, managed identity storage)
- Python v2 programming model with uv
- Triggers and identity-based connections
- Deploy, slots, rollback
- Settings, secrets, security
- Terraform/OpenTofu
- Troubleshooting

## Runtime and plan choice (checked 2026-10-28)

- Host runtime: **4.x** only (1.x support ends 2026-09-14; 2.x/3.x retired; v3 Linux Consumption apps stop 2026-09-30).
- Python 3.13 (recommended, EOS Oct 2029) / 3.14 / 3.12; Node.js 24 / 22. Select only a supported runtime listed for the target Functions host and plan.
- Plans:

| Plan | Use |
|---|---|
| **Flex Consumption (FC1)** | default for new apps: scale to zero, VNet integration, always-ready instances, per-function scaling |
| Premium (EP1-3) | long-running, pre-warmed, Windows/containers needs |
| Dedicated (App Service) | existing App Service plans |
| Linux Consumption (Y1) | **legacy** — no new language versions (Python stops at 3.12), retiring 2028-09-30; migrate to Flex |

## Tooling

```bash
# Azure CLI 2.91.0 and Azure Functions Core Tools 4.16.0 (checked 2026-10-28)
npm install -g azure-functions-core-tools@4.16.0
func --version
```

## Create app (Flex Consumption)

```bash
az storage account create -g <rg> -n <funcsa> -l <region> --sku Standard_ZRS \
  --allow-blob-public-access false --allow-shared-key-access false --min-tls-version TLS1_2
az identity create -g <rg> -n <app>-func-mi
az functionapp create -g <rg> -n <app>-func --flexconsumption-location <region> \
  --runtime python --runtime-version 3.13 \
  --storage-account <funcsa> --deployment-storage-auth-type UserAssignedIdentity \
  --deployment-storage-auth-value <app>-func-mi \
  --assign-identity <mi-resource-id> --instance-memory 2048 --maximum-instance-count 40
az functionapp scale config always-ready set -g <rg> -n <app>-func --settings http=1     # avoid cold starts on HTTP
az functionapp vnet-integration add -g <rg> -n <app>-func --vnet spoke-<env>-vnet --subnet func-integration
```

Grant the identity data-plane roles on the storage account (`Storage Blob Data Owner`, `Storage Queue Data Contributor`, `Storage Table Data Contributor`) and set `AzureWebJobsStorage__accountName=<funcsa>` + `AzureWebJobsStorage__credential=managedidentity` + `AzureWebJobsStorage__clientId=<mi-client-id>` instead of a connection string.

## Python v2 programming model with uv

```
<app>/
  function_app.py
  host.json
  pyproject.toml / uv.lock   # source of truth
  requirements.txt           # generated for deployment
```

```bash
uv export --frozen --no-dev --no-hashes -o requirements.txt
func start            # local; local.settings.json must stay untracked (.gitignore) and hold no real secrets
```

```python
import json
import logging

import azure.functions as func

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)


@app.route(route="health", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def health(req: func.HttpRequest) -> func.HttpResponse:
    return func.HttpResponse('{"status":"ok"}', mimetype="application/json")


@app.service_bus_queue_trigger(arg_name="msg", queue_name="<queue-name>", connection="ServiceBus")
def process_order(msg: func.ServiceBusMessage) -> None:
    payload = json.loads(msg.get_body())
    logging.info("message accepted")   # idempotent processing; at-least-once delivery


@app.timer_trigger(schedule="0 */5 * * * *", arg_name="timer", run_on_startup=False)
def cleanup(timer: func.TimerRequest) -> None:
    if timer.past_due:
        logging.warning("timer past due")
```

Timer CRON has 6 fields (seconds first); timezone via `WEBSITE_TIME_ZONE` (not on Linux Consumption/Flex — use UTC).

## Triggers and identity-based connections

Use `<CONNECTION>__fullyQualifiedNamespace` / `__serviceUri` / `__accountName` settings (+ `__credential=managedidentity`, `__clientId`) instead of connection strings:

| Binding | Setting example | Role for identity |
|---|---|---|
| Service Bus | `ServiceBus__fullyQualifiedNamespace=<ns>.servicebus.windows.net` | Azure Service Bus Data Receiver/Sender |
| Event Hubs | `EventHub__fullyQualifiedNamespace=…` | Azure Event Hubs Data Receiver |
| Blob (event grid source) | `Storage__serviceUri=https://<sa>.blob.core.windows.net` | Storage Blob Data Owner |
| Cosmos DB | `Cosmos__accountEndpoint=https://<acct>.documents.azure.com` | Cosmos DB Built-in Data Contributor |

Blob triggers on Flex must use the Event Grid source (`source="EventGrid"`).

## Deploy, slots, rollback

```bash
func azure functionapp publish <app>-func                 # remote build installs requirements.txt
az functionapp deployment source config-zip -g <rg> -n <app>-func --src build.zip   # CI artefact
```

- GitHub Actions CI: authenticate with workload identity federation (`networking.md` → CI auth); never publish profiles or service-principal secrets.
- Slots: supported on Premium/Dedicated (not Flex — use blue/green apps or traffic via Front Door/APIM). With slots: deploy to `staging`, smoke test `https://<app>-func-staging.azurewebsites.net/api/health`, then `az functionapp deployment slot swap -g <rg> -n <app>-func --slot staging --target-slot production`; swap back to roll back. Mark env-specific settings with `--slot-settings`.

## Settings, secrets, security

```bash
az functionapp config appsettings set -g <rg> -n <app>-func --settings \
  "DB_PASSWORD_REF=@Microsoft.KeyVault(SecretUri=https://<kv>.vault.azure.net/secrets/<name>/)" \
  "APPLICATIONINSIGHTS_CONNECTION_STRING=@Microsoft.KeyVault(SecretUri=https://<kv>.vault.azure.net/secrets/<ai-conn>/)"
az functionapp config set -g <rg> -n <app>-func --min-tls-version 1.2 --ftps-state Disabled
az functionapp update -g <rg> -n <app>-func --set httpsOnly=true
az functionapp cors add -g <rg> -n <app>-func --allowed-origins "https://<frontend-host>"
az resource update -g <rg> -n scm --namespace Microsoft.Web --resource-type basicPublishingCredentialsPolicies \
  --parent sites/<app>-func --set properties.allow=false     # disable basic auth publishing
```

- Key Vault references need the app identity to have `Key Vault Secrets User`.
- `APPINSIGHTS_INSTRUMENTATIONKEY` is retired (ingestion ended 2025-03-31) — use `APPLICATIONINSIGHTS_CONNECTION_STRING` (+ Entra auth for ingestion if required).
- Function keys are shared secrets; for user-facing APIs prefer Easy Auth / APIM in front. Private endpoints for inbound when internal-only.

## Terraform/OpenTofu

```hcl
resource "azurerm_function_app_flex_consumption" "main" {
  name                = "${var.env}-app-func"
  resource_group_name = azurerm_resource_group.fn.name
  location            = azurerm_resource_group.fn.location
  service_plan_id     = azurerm_service_plan.flex.id      # sku_name = "FC1"
  storage_container_type      = "blobContainer"
  storage_container_endpoint  = "${azurerm_storage_account.fn.primary_blob_endpoint}${azurerm_storage_container.deploy.name}"
  storage_authentication_type = "UserAssignedIdentity"
  storage_user_assigned_identity_id = azurerm_user_assigned_identity.fn.id
  runtime_name        = "python"
  runtime_version     = "3.13"
  maximum_instance_count = 40
  instance_memory_in_mb  = 2048
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.fn.id]
  }
  site_config {}
  app_settings = {
    AzureWebJobsStorage__accountName = azurerm_storage_account.fn.name
    AzureWebJobsStorage__credential  = "managedidentity"
    AzureWebJobsStorage__clientId    = azurerm_user_assigned_identity.fn.client_id
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.main.connection_string
  }
}
```

AzureRM provider `5.11.0` (checked 2026-10-28); pin this exact version and validate resource attributes against its provider documentation.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `ModuleNotFoundError` | `requirements.txt` missing/out of date (regenerate from `uv.lock`); remote build enabled |
| Trigger never fires | identity role missing on source; wrong `__fullyQualifiedNamespace`; Flex blob needs Event Grid |
| 401 on HTTP | auth level vs key; Easy Auth config |
| Cold starts | Flex always-ready / Premium pre-warmed |
| Storage 403 on start | `--allow-shared-key-access false` without identity-based `AzureWebJobsStorage` |
| Timer runs twice | singleton via blob lease is default; check multiple apps sharing one storage account + same host ID |
| Can't create Python 3.13 on Y1 | Linux Consumption is frozen at 3.12 — use Flex |
