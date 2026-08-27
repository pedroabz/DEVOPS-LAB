using System.Net;
using System.Net.Http.Json;

namespace DevOpsLab.Bff.Orders;

public sealed class OrdersApiClient
{
    private readonly HttpClient _http;

    public OrdersApiClient(HttpClient http) => _http = http;

    public async Task<IReadOnlyList<OrderResponse>> ListAsync(CancellationToken cancellationToken)
        => await _http.GetFromJsonAsync<IReadOnlyList<OrderResponse>>("/orders", cancellationToken)
           ?? [];

    /// <summary>
    /// Returns null when the API rejects the order as invalid, so the caller can translate that
    /// into the same 400 the API would have produced rather than a 500.
    /// </summary>
    public async Task<OrderResponse?> CreateAsync(
        CreateOrderRequest request,
        CancellationToken cancellationToken)
    {
        var response = await _http.PostAsJsonAsync("/orders", request, cancellationToken);

        if (response.StatusCode == HttpStatusCode.BadRequest)
        {
            return null;
        }

        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<OrderResponse>(cancellationToken);
    }
}
