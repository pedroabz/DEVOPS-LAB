using Azure.Core;

namespace DevOpsLab.Bff.Orders;

/// <summary>
/// Supplies the access token the BFF uses to call the Orders API, as itself.
/// </summary>
/// <remarks>
/// <para>
/// This is a client-credentials token obtained through the BFF's managed identity. It says "I am
/// the BFF" and carries nothing about the signed-in user — by design. The API never learns who the
/// user is; all per-user authorisation happens here, before this token is ever requested.
/// </para>
/// <para>
/// The cache is not an optimisation. Entra throttles token requests per application, so acquiring
/// one per inbound call starts returning 429 under any real traffic.
/// </para>
/// </remarks>
public sealed class ApiTokenProvider
{
    /// <summary>
    /// Refresh this far ahead of expiry so a token cannot lapse mid-flight. Calls through this BFF
    /// can legitimately take a minute when the Orders API is waiting on a paused serverless
    /// database to resume.
    /// </summary>
    private static readonly TimeSpan RefreshSkew = TimeSpan.FromMinutes(5);

    private readonly TokenCredential _credential;
    private readonly TimeProvider _timeProvider;
    private readonly string[] _scopes;
    private readonly SemaphoreSlim _refreshLock = new(1, 1);

    private AccessToken _token;

    public ApiTokenProvider(TokenCredential credential, TimeProvider timeProvider, string scope)
    {
        _credential = credential;
        _timeProvider = timeProvider;
        _scopes = [scope];
    }

    public async Task<string> GetTokenAsync(CancellationToken cancellationToken)
    {
        if (IsUsable(_token))
        {
            return _token.Token;
        }

        await _refreshLock.WaitAsync(cancellationToken);
        try
        {
            // Re-check inside the lock: while this caller waited, another may already have
            // refreshed, and a second request would be wasted throttle budget.
            if (IsUsable(_token))
            {
                return _token.Token;
            }

            _token = await _credential.GetTokenAsync(new TokenRequestContext(_scopes), cancellationToken);
            return _token.Token;
        }
        finally
        {
            _refreshLock.Release();
        }
    }

    private bool IsUsable(AccessToken token)
        => !string.IsNullOrEmpty(token.Token)
           && token.ExpiresOn - _timeProvider.GetUtcNow() > RefreshSkew;
}
