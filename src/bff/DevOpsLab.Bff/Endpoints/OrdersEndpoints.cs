using DevOpsLab.Bff.Configuration;
using DevOpsLab.Bff.Orders;
using Microsoft.AspNetCore.Http.HttpResults;

namespace DevOpsLab.Bff.Endpoints;

public static class OrdersEndpoints
{
    /// <summary>
    /// Deliberately narrower than the Orders API. A backend-for-frontend exposes what one client
    /// needs, not a mirror of everything behind it — the transitions, quantity change and delete
    /// stay API-only.
    /// </summary>
    public static RouteGroupBuilder MapOrders(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/api/orders").WithTags("Orders");

        group.MapGet("/", async (OrdersApiClient api, CancellationToken cancellationToken)
                => TypedResults.Ok(await api.ListAsync(cancellationToken)))
            .RequireAuthorization(BffAuthentication.OrdersReadPolicy);

        group.MapPost("/", async Task<Results<Created<OrderResponse>, ValidationProblem>> (
                CreateOrderRequest request,
                OrdersApiClient api,
                CancellationToken cancellationToken) =>
            {
                var order = await api.CreateAsync(request, cancellationToken);

                // The API validates too. Passing its rejection through as a 400 keeps the contract
                // the SPA sees identical to the one the API promises.
                return order is null
                    ? TypedResults.ValidationProblem(new Dictionary<string, string[]>
                    {
                        ["request"] = ["The Orders API rejected this order as invalid."]
                    })
                    : TypedResults.Created($"/api/orders/{order.Id}", order);
            })
            // Admin only. This is the single route where Orders.Reader and Orders.Admin differ,
            // and therefore the thing that makes the two roles mean anything.
            .RequireAuthorization(BffAuthentication.OrdersWritePolicy);

        return group;
    }
}
