using Microsoft.AspNetCore.Authentication.JwtBearer;

namespace DevOpsLab.Api.Configuration;

/// <summary>
/// Entra ID token validation for the Orders API.
/// </summary>
/// <remarks>
/// <para>
/// The API never learns which human is behind a request. It answers one question — "are you an
/// allowed caller?" — and there are exactly two allowed callers: the BFF, presenting an app-only
/// token, and an administrator with a direct token. Per-user authorisation lives in the BFF.
/// </para>
/// <para>
/// Deliberately uses <c>Microsoft.AspNetCore.Authentication.JwtBearer</c> rather than
/// <c>Microsoft.Identity.Web</c>. This API acquires no tokens, calls no downstream API and has no
/// user, so most of that library is unused — and its implicit defaults are exactly what makes an
/// unexplained 401 hard to diagnose.
/// </para>
/// </remarks>
public static class ApiAuthentication
{
    public const string TenantIdKey = "AzureAd:TenantId";
    public const string ClientIdKey = "AzureAd:ClientId";

    /// <summary>Claim carrying app roles. Not a namespaced URI — see <see cref="AddApiAuthentication"/>.</summary>
    public const string RolesClaimType = "roles";

    public const string OrdersAccessPolicy = "OrdersAccess";

    /// <summary>Held by the BFF's managed identity.</summary>
    public const string FullAccessRole = "Orders.FullAccess";

    /// <summary>Held by an administrator calling the API without going through the BFF.</summary>
    public const string AdminDirectRole = "Orders.Admin.Direct";

    public static IServiceCollection AddApiAuthentication(
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
                // The /v2.0 suffix pairs with requestedAccessTokenVersion: 2 on the app
                // registration in iac/modules/entraApps.bicep. Without it Entra issues v1 tokens
                // whose issuer is https://sts.windows.net/{tid}/, which never matches metadata
                // fetched from a /v2.0 authority — every call 401s with nothing useful logged.
                options.Authority = $"https://login.microsoftonline.com/{tenantId}/v2.0";

                // With v2 tokens the audience is the application's client ID, NOT its identifier
                // URI. This single line is also what makes the API reject a token minted for the
                // SPA or the BFF: their audience is a different GUID.
                options.Audience = clientId;

                // JwtBearer otherwise rewrites "roles" to the WS-Federation claim URI, after
                // which RequireClaim(RolesClaimType, ...) matches nothing and every authorised
                // caller gets a 403 that looks like a permissions problem.
                options.MapInboundClaims = false;
            });

        services.AddAuthorization(options =>
        {
            // Multiple values in RequireClaim are OR, so this reads "holds either role".
            options.AddPolicy(
                OrdersAccessPolicy,
                policy => policy.RequireClaim(RolesClaimType, FullAccessRole, AdminDirectRole));

            // Fail closed: anything not explicitly opened is protected. The endpoints that are
            // genuinely anonymous say so at the point they are mapped, which makes the exceptions
            // visible rather than implied by their absence.
            options.FallbackPolicy = options.GetPolicy(OrdersAccessPolicy);
        });

        return services;
    }
}
