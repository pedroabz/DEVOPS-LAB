using System.Security.Claims;
using DevOpsLab.Api.Configuration;
using Microsoft.AspNetCore.Authorization;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace DevOpsLab.Api.Tests;

/// <summary>
/// Exercises the real policy from <see cref="ApiAuthentication"/> rather than a copy of it, so a
/// change to the role names in production code fails here instead of passing silently.
/// </summary>
public sealed class ApiAuthenticationTests
{
    private static IAuthorizationService BuildAuthorizationService()
    {
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                [ApiAuthentication.TenantIdKey] = "00000000-0000-0000-0000-000000000000",
                [ApiAuthentication.ClientIdKey] = "11111111-1111-1111-1111-111111111111",
            })
            .Build();

        var services = new ServiceCollection();
        services.AddLogging();
        services.AddApiAuthentication(configuration);

        return services.BuildServiceProvider().GetRequiredService<IAuthorizationService>();
    }

    // MapInboundClaims is disabled in production, so roles arrive under the bare claim type.
    // Building the principal the same way keeps the test honest about what the API actually sees.
    private static ClaimsPrincipal APrincipalHolding(params string[] roles)
    {
        var claims = roles.Select(role => new Claim(ApiAuthentication.RolesClaimType, role));
        return new ClaimsPrincipal(new ClaimsIdentity(claims, authenticationType: "Test"));
    }

    [Theory]
    [InlineData(ApiAuthentication.FullAccessRole)]
    [InlineData(ApiAuthentication.AdminDirectRole)]
    public async Task OrdersAccess_admits_a_caller_holding_either_allowed_role(string role)
    {
        var authorization = BuildAuthorizationService();

        var result = await authorization.AuthorizeAsync(
            APrincipalHolding(role), resource: null, ApiAuthentication.OrdersAccessPolicy);

        Assert.True(result.Succeeded);
    }

    [Fact]
    public async Task OrdersAccess_refuses_a_caller_holding_neither_role()
    {
        var authorization = BuildAuthorizationService();

        var result = await authorization.AuthorizeAsync(
            APrincipalHolding("Orders.Reader"), resource: null, ApiAuthentication.OrdersAccessPolicy);

        Assert.False(result.Succeeded);
    }

    [Fact]
    public async Task OrdersAccess_refuses_a_caller_with_no_roles_at_all()
    {
        var authorization = BuildAuthorizationService();

        var result = await authorization.AuthorizeAsync(
            APrincipalHolding(), resource: null, ApiAuthentication.OrdersAccessPolicy);

        Assert.False(result.Succeeded);
    }
}
