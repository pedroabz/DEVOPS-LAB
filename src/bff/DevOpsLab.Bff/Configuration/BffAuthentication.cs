using Microsoft.AspNetCore.Authentication.JwtBearer;

namespace DevOpsLab.Bff.Configuration;

/// <summary>
/// Validates the signed-in user's token and decides what that user may do.
/// </summary>
/// <remarks>
/// This is the only place in the system that knows about users. The Orders API sees a token from
/// the BFF's managed identity and nothing else, so a request that reaches it has already been
/// authorised here — there is no second line of defence downstream.
/// </remarks>
public static class BffAuthentication
{
    public const string TenantIdKey = "AzureAd:TenantId";
    public const string ClientIdKey = "AzureAd:ClientId";

    public const string RolesClaimType = "roles";
    public const string ScopeClaimType = "scp";
    public const string RequiredScope = "access_as_user";

    public const string OrdersReadPolicy = "OrdersRead";
    public const string OrdersWritePolicy = "OrdersWrite";

    public const string ReaderRole = "Orders.Reader";
    public const string AdminRole = "Orders.Admin";

    public static IServiceCollection AddBffAuthentication(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        var tenantId = configuration[TenantIdKey]
            ?? throw new InvalidOperationException($"'{TenantIdKey}' is not configured.");
        var clientId = configuration[ClientIdKey]
            ?? throw new InvalidOperationException($"'{ClientIdKey}' is not configured.");

        services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
            .AddJwtBearer(options =>
            {
                // Pairs with requestedAccessTokenVersion: 2 on the app registration. Without the
                // /v2.0 suffix the issuer in the token never matches this authority's metadata and
                // every call 401s with nothing useful logged.
                options.Authority = $"https://login.microsoftonline.com/{tenantId}/v2.0";

                // The BFF's own client ID. A token minted for the Orders API has a different
                // audience and is rejected here — the two are not interchangeable in either
                // direction, which is the whole point of the design.
                options.Audience = clientId;

                // JwtBearer otherwise renames "roles" to the WS-Federation claim URI, after which
                // the policies below match nothing and every user gets a 403.
                options.MapInboundClaims = false;
            });

        services.AddAuthorization(options =>
        {
            options.AddPolicy(OrdersReadPolicy, policy => policy
                .RequireAssertion(HasRequiredScope)
                .RequireClaim(RolesClaimType, ReaderRole, AdminRole));

            options.AddPolicy(OrdersWritePolicy, policy => policy
                .RequireAssertion(HasRequiredScope)
                .RequireClaim(RolesClaimType, AdminRole));
        });

        return services;
    }

    /// <summary>
    /// Checks the scope claim by splitting on whitespace.
    /// </summary>
    /// <remarks>
    /// <c>scp</c> is a single space-delimited claim, not a repeated one, so
    /// <c>RequireClaim("scp", "access_as_user")</c> would compare against the whole string. That
    /// happens to work while there is exactly one scope and breaks silently the moment a second
    /// is added.
    /// </remarks>
    private static bool HasRequiredScope(Microsoft.AspNetCore.Authorization.AuthorizationHandlerContext context)
        => context.User.FindFirst(ScopeClaimType)?.Value
            .Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .Contains(RequiredScope) ?? false;
}
