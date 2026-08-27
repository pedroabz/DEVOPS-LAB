using Azure.Monitor.OpenTelemetry.AspNetCore;
using DevOpsLab.Bff.Configuration;
using DevOpsLab.Bff.Endpoints;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;

const string TelemetryConnectionStringKey = "APPLICATIONINSIGHTS_CONNECTION_STRING";
const string AllowedOriginKey = "Cors:AllowedOrigin";
const string SpaCorsPolicy = "Spa";

var builder = WebApplication.CreateBuilder(args);

// iac/modules/bffAppService.bicep supplies this as an app setting. Nothing supplies it locally,
// and UseAzureMonitor() THROWS at startup rather than degrading when it is missing — so the call
// is guarded, exactly as in the Orders API.
if (!string.IsNullOrWhiteSpace(builder.Configuration[TelemetryConnectionStringKey]))
{
    builder.Services.AddOpenTelemetry().UseAzureMonitor();
}

builder.Services.AddBffAuthentication(builder.Configuration);
builder.Services.AddOrdersApiClient(builder.Configuration);

// The SPA is served from Static Web Apps, a different origin from this BFF. Without this, every
// call from the browser fails preflight.
var allowedOrigin = builder.Configuration[AllowedOriginKey];
builder.Services.AddCors(options => options.AddPolicy(SpaCorsPolicy, policy =>
{
    if (!string.IsNullOrWhiteSpace(allowedOrigin))
    {
        policy.WithOrigins(allowedOrigin).AllowAnyHeader().WithMethods("GET", "POST");
    }
}));

builder.Services.AddProblemDetails();
builder.Services.AddHealthChecks();

var app = builder.Build();

app.UseExceptionHandler();

// Before UseAuthentication, because a preflight OPTIONS carries no token. Behind authentication it
// would get a 401, and the browser would report a CORS failure that has nothing to do with CORS.
app.UseCors(SpaCorsPolicy);

app.UseAuthentication();
app.UseAuthorization();

// No /health/ready here. A readiness check that called the Orders API would make one app's probe
// failure cascade into the other, so the BFF only reports whether its own process is alive.
app.MapHealthChecks("/health/live", new HealthCheckOptions { Predicate = _ => false })
    .AllowAnonymous();

app.MapOrders();

app.Run();
