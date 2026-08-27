using DevOpsLab.Application.Orders;
using DevOpsLab.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace DevOpsLab.Infrastructure;

public static class DependencyInjection
{
    /// <summary>
    /// Name of the connection string. Matches the App Service connection string declared in
    /// iac/modules/appService.bicep, which arrives as ConnectionStrings:DefaultConnection.
    /// </summary>
    public const string ConnectionStringName = "DefaultConnection";

    public static IServiceCollection AddInfrastructure(this IServiceCollection services, IConfiguration configuration)
    {
        var connectionString = configuration.GetConnectionString(ConnectionStringName)
            ?? throw new InvalidOperationException(
                $"Connection string '{ConnectionStringName}' is not configured.");

        services.AddDbContext<OrdersDbContext>(options =>
            options.UseSqlServer(connectionString, SqlServerOptions));

        services.AddScoped<IOrderRepository, OrderRepository>();

        return services;
    }

    /// <summary>
    /// Tag marking checks that belong on readiness rather than liveness.
    /// </summary>
    public const string ReadinessTag = "ready";

    /// <summary>
    /// Registered here rather than in the API so <see cref="OrdersDbContext"/> stays inside this
    /// assembly.
    /// </summary>
    /// <remarks>
    /// This calls <c>CanConnectAsync</c>, which runs through the retry strategy configured in
    /// <see cref="SqlServerOptions"/>. While the serverless database is resuming, the check can
    /// therefore take a minute or more to answer rather than failing fast. Acceptable on readiness;
    /// it is why nothing SQL-touching goes on liveness.
    /// </remarks>
    public static IHealthChecksBuilder AddInfrastructureHealthChecks(this IHealthChecksBuilder builder)
        => builder.AddDbContextCheck<OrdersDbContext>(name: "sql", tags: [ReadinessTag]);

    /// <summary>
    /// Shared by the app and by the design-time factory so both talk to SQL the same way.
    /// </summary>
    internal static void SqlServerOptions(Microsoft.EntityFrameworkCore.Infrastructure.SqlServerDbContextOptionsBuilder sqlServer)
    {
        // The database is serverless with 60-minute auto-pause (see docs/adr/0001). Resuming takes
        // 30-60 seconds and the first connection fails rather than waiting, so the retry window has
        // to outlast a resume. Eight retries with exponential backoff capped at 30s per attempt
        // clears 60s comfortably; without this the first request after an idle period returns 500.
        sqlServer.EnableRetryOnFailure(
            maxRetryCount: 8,
            maxRetryDelay: TimeSpan.FromSeconds(30),
            errorNumbersToAdd: null);

        sqlServer.MigrationsAssembly(typeof(DependencyInjection).Assembly.FullName);
    }
}
