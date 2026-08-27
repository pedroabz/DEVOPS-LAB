using DevOpsLab.Application.Orders;
using DevOpsLab.Domain.Orders;
using Microsoft.AspNetCore.Http.HttpResults;

namespace DevOpsLab.Api.Endpoints;

public static class OrdersEndpoints
{
    public static RouteGroupBuilder MapOrders(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/orders").WithTags("Orders");

        group.MapGet("/", async (OrderService orders, CancellationToken cancellationToken)
            => TypedResults.Ok(await orders.ListAsync(cancellationToken)));

        group.MapGet("/{id:guid}", async Task<Results<Ok<OrderResponse>, NotFound>> (
            Guid id,
            OrderService orders,
            CancellationToken cancellationToken) =>
        {
            var order = await orders.GetAsync(id, cancellationToken);
            return order is null ? TypedResults.NotFound() : TypedResults.Ok(order);
        });

        group.MapPost("/", async Task<Results<Created<OrderResponse>, ValidationProblem>> (
            CreateOrderRequest request,
            OrderService orders,
            CancellationToken cancellationToken) =>
        {
            // The domain validates too. This catch translates its ArgumentException into the 400 that
            // the endpoint contract promises, rather than letting it surface as a 500.
            try
            {
                var order = await orders.CreateAsync(request, cancellationToken);
                return TypedResults.Created($"/orders/{order.Id}", order);
            }
            catch (ArgumentException ex)
            {
                return ValidationProblemFor(ex);
            }
        });

        group.MapPut("/{id:guid}/quantity", async Task<Results<Ok<OrderResponse>, NotFound, ValidationProblem, Conflict<string>>> (
            Guid id,
            UpdateOrderQuantityRequest request,
            OrderService orders,
            CancellationToken cancellationToken) =>
        {
            try
            {
                var order = await orders.ChangeQuantityAsync(id, request, cancellationToken);
                return order is null ? TypedResults.NotFound() : TypedResults.Ok(order);
            }
            catch (ArgumentException ex)
            {
                return ValidationProblemFor(ex);
            }
            catch (InvalidOrderStateException ex)
            {
                return TypedResults.Conflict(ex.Message);
            }
        });

        MapTransition(group, "confirm", (orders, id, token) => orders.ConfirmAsync(id, token));
        MapTransition(group, "ship", (orders, id, token) => orders.ShipAsync(id, token));
        MapTransition(group, "cancel", (orders, id, token) => orders.CancelAsync(id, token));

        group.MapDelete("/{id:guid}", async Task<Results<NoContent, NotFound>> (
            Guid id,
            OrderService orders,
            CancellationToken cancellationToken) =>
        {
            var deleted = await orders.DeleteAsync(id, cancellationToken);
            return deleted ? TypedResults.NoContent() : TypedResults.NotFound();
        });

        return group;
    }

    /// <summary>
    /// The three status transitions differ only in which method they call, so they share a shape:
    /// POST /orders/{id}/{verb} with 404 for unknown and 409 for a transition the order refuses.
    /// </summary>
    private static void MapTransition(
        RouteGroupBuilder group,
        string verb,
        Func<OrderService, Guid, CancellationToken, Task<OrderResponse?>> transition)
    {
        group.MapPost($"/{{id:guid}}/{verb}", async Task<Results<Ok<OrderResponse>, NotFound, Conflict<string>>> (
            Guid id,
            OrderService orders,
            CancellationToken cancellationToken) =>
        {
            try
            {
                var order = await transition(orders, id, cancellationToken);
                return order is null ? TypedResults.NotFound() : TypedResults.Ok(order);
            }
            catch (InvalidOrderStateException ex)
            {
                return TypedResults.Conflict(ex.Message);
            }
        });
    }

    private static ValidationProblem ValidationProblemFor(ArgumentException ex)
        => TypedResults.ValidationProblem(new Dictionary<string, string[]>
        {
            [ex.ParamName ?? "request"] = [ex.Message]
        });
}
