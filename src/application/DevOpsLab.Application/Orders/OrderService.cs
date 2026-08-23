using DevOpsLab.Domain.Orders;

namespace DevOpsLab.Application.Orders;

public sealed class OrderService
{
    private readonly IOrderRepository _repository;
    private readonly TimeProvider _timeProvider;

    public OrderService(IOrderRepository repository, TimeProvider timeProvider)
    {
        _repository = repository;
        _timeProvider = timeProvider;
    }

    public async Task<IReadOnlyList<OrderResponse>> ListAsync(CancellationToken cancellationToken)
    {
        var orders = await _repository.ListAsync(cancellationToken);
        return orders.Select(ToResponse).ToList();
    }

    public async Task<OrderResponse?> GetAsync(Guid id, CancellationToken cancellationToken)
    {
        var order = await _repository.GetAsync(id, cancellationToken);
        return order is null ? null : ToResponse(order);
    }

    public async Task<OrderResponse> CreateAsync(CreateOrderRequest request, CancellationToken cancellationToken)
    {
        var order = Order.Create(
            request.CustomerName,
            request.Product,
            request.Quantity,
            request.UnitPrice,
            _timeProvider.GetUtcNow());

        await _repository.AddAsync(order, cancellationToken);
        await _repository.SaveChangesAsync(cancellationToken);

        return ToResponse(order);
    }

    public Task<OrderResponse?> ChangeQuantityAsync(
        Guid id,
        UpdateOrderQuantityRequest request,
        CancellationToken cancellationToken)
        => MutateAsync(id, order => order.ChangeQuantity(request.Quantity), cancellationToken);

    public Task<OrderResponse?> ConfirmAsync(Guid id, CancellationToken cancellationToken)
        => MutateAsync(id, order => order.Confirm(), cancellationToken);

    public Task<OrderResponse?> ShipAsync(Guid id, CancellationToken cancellationToken)
        => MutateAsync(id, order => order.Ship(), cancellationToken);

    public Task<OrderResponse?> CancelAsync(Guid id, CancellationToken cancellationToken)
        => MutateAsync(id, order => order.Cancel(), cancellationToken);

    /// <returns><c>false</c> when no order with that id exists.</returns>
    public async Task<bool> DeleteAsync(Guid id, CancellationToken cancellationToken)
    {
        var order = await _repository.GetAsync(id, cancellationToken);
        if (order is null)
        {
            return false;
        }

        await _repository.RemoveAsync(order, cancellationToken);
        await _repository.SaveChangesAsync(cancellationToken);
        return true;
    }

    /// <summary>
    /// Load, apply a domain operation, save. Returns <c>null</c> when the order does not exist;
    /// a rejected transition surfaces as <see cref="InvalidOrderStateException"/> from <paramref name="operation"/>.
    /// </summary>
    private async Task<OrderResponse?> MutateAsync(
        Guid id,
        Action<Order> operation,
        CancellationToken cancellationToken)
    {
        var order = await _repository.GetAsync(id, cancellationToken);
        if (order is null)
        {
            return null;
        }

        operation(order);
        await _repository.SaveChangesAsync(cancellationToken);

        return ToResponse(order);
    }

    private static OrderResponse ToResponse(Order order) => new(
        order.Id,
        order.CustomerName,
        order.Product,
        order.Quantity,
        order.UnitPrice,
        order.Total,
        order.Status.ToString(),
        order.CreatedAt);
}
