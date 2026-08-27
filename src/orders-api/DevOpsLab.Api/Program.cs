using Azure.Monitor.OpenTelemetry.AspNetCore;
using DevOpsLab.Api.Configuration;
using DevOpsLab.Api.Endpoints;
using DevOpsLab.Application.Orders;
using DevOpsLab.Infrastructure;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Scalar.AspNetCore;

const string TelemetryConnectionStringKey = "APPLICATIONINSIGHTS_CONNECTION_STRING";

var builder = WebApplication.CreateBuilder(args);

// Configuration has to be assembled before the host exists, so this logger writes to the console
// only. Telemetry starts below, once the container is being built.
using (var startupLoggerFactory = LoggerFactory.Create(logging => logging.AddConsole()))
{
    builder.Configuration.AddKeyVaultIfConfigured(startupLoggerFactory.CreateLogger("Startup"));
}

// iac/modules/appService.bicep supplies APPLICATIONINSIGHTS_CONNECTION_STRING as an app setting.
// Nothing supplies it locally, and UseAzureMonitor() THROWS at startup rather than degrading when
// it is missing — so guard the call instead of letting `dotnet run` fail on a dev machine.
if (!string.IsNullOrWhiteSpace(builder.Configuration[TelemetryConnectionStringKey]))
{
    builder.Services.AddOpenTelemetry().UseAzureMonitor();
}

builder.Services.AddInfrastructure(builder.Configuration);
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddScoped<OrderService>();

builder.Services.AddProblemDetails();
builder.Services.AddOpenApi();
builder.Services.AddHealthChecks().AddInfrastructureHealthChecks();
builder.Services.AddApiAuthentication(builder.Configuration);

var app = builder.Build();

// Turns an unhandled exception into a ProblemDetails response instead of an empty 500.
app.UseExceptionHandler();

app.UseAuthentication();
app.UseAuthorization();

// The Web App is public on the internet until v3 puts APIM in front of it, so the API surface is
// only described where it cannot be browsed by strangers.
if (app.Environment.IsDevelopment())
{
    // AllowAnonymous because ApiAuthentication sets a fallback policy — without these the API
    // description and its UI would demand a token, which breaks local exploration.
    app.MapOpenApi().AllowAnonymous();
    app.MapScalarApiReference().AllowAnonymous();
}

// Liveness answers one question: is this process able to serve traffic at all? It deliberately runs
// NO checks — App Service restarts instances that fail healthCheckPath, and a check that touched the
// serverless database would turn every auto-pause into a restart loop.
// Anonymous on purpose: App Service's healthCheckPath probe and the api-cd smoke test have no
// token, and a health endpoint that 401s would make a healthy instance look dead.
app.MapHealthChecks("/health/live", new HealthCheckOptions { Predicate = _ => false })
    .AllowAnonymous();

// Readiness additionally proves SQL is reachable. Slow during an auto-pause resume by design.
app.MapHealthChecks("/health/ready", new HealthCheckOptions
{
    Predicate = check => check.Tags.Contains(DependencyInjection.ReadinessTag)
}).AllowAnonymous();

app.MapOrders();

app.Run();
