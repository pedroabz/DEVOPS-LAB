using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace DevOpsLab.Infrastructure.Persistence;

/// <summary>
/// Used only by the <c>dotnet ef</c> tooling, which needs a DbContext without starting the API.
/// </summary>
/// <remarks>
/// <para>
/// <c>dotnet ef migrations add</c> only reads the model, so the connection string it gets never has
/// to be reachable — hence the localhost fallback, which keeps scaffolding a migration an offline
/// operation.
/// </para>
/// <para>
/// <c>dotnet ef database update</c> does connect. Point it at the real server by setting
/// <c>ORDERS_CONNECTION_STRING</c> first. SQL is Entra-only, so the value should use
/// <c>Authentication=Active Directory Default</c> and you must be signed in with <c>az login</c> as
/// a member of the SQL admin group.
/// </para>
/// </remarks>
public sealed class OrdersDbContextFactory : IDesignTimeDbContextFactory<OrdersDbContext>
{
    public const string ConnectionStringVariable = "ORDERS_CONNECTION_STRING";

    private const string OfflineFallback =
        "Server=localhost;Database=DevOpsLabOrders;Trusted_Connection=True;TrustServerCertificate=True;";

    public OrdersDbContext CreateDbContext(string[] args)
    {
        var connectionString =
            Environment.GetEnvironmentVariable(ConnectionStringVariable) ?? OfflineFallback;

        var options = new DbContextOptionsBuilder<OrdersDbContext>()
            .UseSqlServer(connectionString, DependencyInjection.SqlServerOptions)
            .Options;

        return new OrdersDbContext(options);
    }
}
