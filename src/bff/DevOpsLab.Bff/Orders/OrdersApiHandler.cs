using System.Net.Http.Headers;

namespace DevOpsLab.Bff.Orders;

/// <summary>
/// Attaches the BFF's own access token to every outbound call.
/// </summary>
/// <remarks>
/// A handler rather than something the client does per call, so there is exactly one place where a
/// token can be attached — and therefore no way to add a request that accidentally forwards the
/// user's token instead.
/// </remarks>
public sealed class OrdersApiHandler : DelegatingHandler
{
    private readonly ApiTokenProvider _tokenProvider;

    public OrdersApiHandler(ApiTokenProvider tokenProvider) => _tokenProvider = tokenProvider;

    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        var token = await _tokenProvider.GetTokenAsync(cancellationToken);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return await base.SendAsync(request, cancellationToken);
    }
}
