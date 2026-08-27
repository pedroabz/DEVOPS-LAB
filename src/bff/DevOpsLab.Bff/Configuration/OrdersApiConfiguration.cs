using Azure.Core;
using Azure.Identity;
using DevOpsLab.Bff.Orders;

namespace DevOpsLab.Bff.Configuration;

/// <summary>
/// Wires up the outbound half: how the BFF reaches the Orders API, and as whom.
/// </summary>
public static class OrdersApiConfiguration
{
    public const string BaseUrlKey = "OrdersApi:BaseUrl";
    public const string ScopeKey = "OrdersApi:Scope";

    public static IServiceCollection AddOrdersApiClient(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        var baseUrl = configuration[BaseUrlKey]
            ?? throw new InvalidOperationException($"'{BaseUrlKey}' is not configured.");
        var scope = configuration[ScopeKey]
            ?? throw new InvalidOperationException($"'{ScopeKey}' is not configured.");

        services.AddSingleton(TimeProvider.System);

        // Singleton: a credential constructed per request re-authenticates against IMDS every
        // time, discarding the SDK's own caching along with ours.
        services.AddSingleton<TokenCredential>(new DefaultAzureCredential());

        services.AddSingleton(provider => new ApiTokenProvider(
            provider.GetRequiredService<TokenCredential>(),
            provider.GetRequiredService<TimeProvider>(),
            scope));

        services.AddTransient<OrdersApiHandler>();

        services.AddHttpClient<OrdersApiClient>(client =>
            {
                client.BaseAddress = new Uri(baseUrl);

                // Generous because the Orders API may itself be waiting on a serverless database
                // to resume, which takes 30-60 seconds.
                client.Timeout = TimeSpan.FromSeconds(100);
            })
            .AddHttpMessageHandler<OrdersApiHandler>();

        return services;
    }
}
