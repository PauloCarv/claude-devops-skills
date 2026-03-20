# Application Insights Instrumentation

## .NET / ASP.NET Core

```bash
dotnet add package Microsoft.ApplicationInsights.AspNetCore
```

```csharp
// Program.cs
builder.Services.AddApplicationInsightsTelemetry(options =>
{
    options.ConnectionString = builder.Configuration["ApplicationInsights:ConnectionString"];
    // Use Key Vault reference: @Microsoft.KeyVault(SecretUri=...)
});

// Adaptive sampling (reduces costs in production)
builder.Services.Configure<TelemetryConfiguration>(config =>
{
    config.DefaultTelemetrySink.TelemetryProcessorChainBuilder
        .UseAdaptiveSampling(maxTelemetryItemsPerSecond: 5)
        .Build();
});
```

```csharp
// Custom telemetry
public class OrderService
{
    private readonly TelemetryClient _telemetry;

    public async Task ProcessOrder(Order order)
    {
        using var operation = _telemetry.StartOperation<RequestTelemetry>("ProcessOrder");
        operation.Telemetry.Properties["OrderId"] = order.Id.ToString();

        try
        {
            // logic...
            _telemetry.TrackEvent("OrderProcessed", new Dictionary<string, string>
            {
                ["OrderId"] = order.Id.ToString(),
                ["Amount"] = order.Total.ToString()
            });
        }
        catch (Exception ex)
        {
            _telemetry.TrackException(ex);
            operation.Telemetry.Success = false;
            throw;
        }
    }
}
```

## Node.js / TypeScript

```bash
npm install @azure/monitor-opentelemetry
```

```typescript
// instrumentation.ts — import BEFORE everything else
import { useAzureMonitor } from "@azure/monitor-opentelemetry";

useAzureMonitor({
  azureMonitorExporterOptions: {
    connectionString: process.env.APPLICATIONINSIGHTS_CONNECTION_STRING,
  },
  samplingRatio: process.env.NODE_ENV === "production" ? 0.1 : 1.0,
});
```

```typescript
// Custom telemetry with OpenTelemetry
import { trace, metrics } from "@opentelemetry/api";

const tracer = trace.getTracer("meu-servico");
const meter = metrics.getMeter("meu-servico");
const requestCounter = meter.createCounter("requests_total");

async function processRequest(req: Request) {
  const span = tracer.startSpan("processRequest");
  requestCounter.add(1, { endpoint: req.url });

  try {
    // logic...
    span.setStatus({ code: SpanStatusCode.OK });
  } catch (err) {
    span.recordException(err as Error);
    span.setStatus({ code: SpanStatusCode.ERROR });
    throw err;
  } finally {
    span.end();
  }
}
```

## Python

```bash
pip install azure-monitor-opentelemetry
```

```python
# main.py — first line
from azure.monitor.opentelemetry import configure_azure_monitor
configure_azure_monitor(
    connection_string=os.environ["APPLICATIONINSIGHTS_CONNECTION_STRING"]
)

# FastAPI — auto-instrumented after configure_azure_monitor()
from fastapi import FastAPI
app = FastAPI()
```

## Connection String via Key Vault (production)

```bash
# Store in Key Vault
az keyvault secret set \
  --vault-name <kv-name> \
  --name "AppInsights-ConnectionString" \
  --value "$(az monitor app-insights component show \
    --app <ai-name> -g <rg> \
    --query connectionString -o tsv)"
```

```hcl
# Container App — Key Vault reference (without exposing the string)
resource "azurerm_container_app" "this" {
  secret {
    name                = "appinsights-connection-string"
    key_vault_secret_id = azurerm_key_vault_secret.appinsights.id
    identity            = azurerm_user_assigned_identity.this.id
  }

  template {
    container {
      env {
        name        = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        secret_name = "appinsights-connection-string"
      }
    }
  }
}
```
