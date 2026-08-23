using DevOpsLab.Application.Orders;
using DevOpsLab.Domain.Orders;
using Microsoft.Extensions.Time.Testing;
using NSubstitute;

namespace DevOpsLab.Api.Tests;

public sealed class OrderServiceTests
{
    private static readonly DateTimeOffset Now = new(2026, 8, 23, 12, 0, 0, TimeSpan.Zero);

    private readonly IOrderRepository _repository = Substitute.For<IOrderRepository>();
    private readonly OrderService _service;

    public OrderServiceTests()
    {
        _service = new OrderService(_repository, new FakeTimeProvider(Now));
    }

    private static Order AnOrder(int quantity = 2) =>
        Order.Create("Ada Lovelace", "Analytical Engine", quantity, 10.50m, Now);

    [Fact]
    public async Task CreateAsync_stamps_the_order_with_the_injected_clock()
    {
        var request = new CreateOrderRequest("Ada Lovelace", "Analytical Engine", 2, 10.50m);

        var response = await _service.CreateAsync(request, CancellationToken.None);

        Assert.Equal(Now, response.CreatedAt);
        Assert.Equal(nameof(OrderStatus.Pending), response.Status);
        Assert.Equal(21.00m, response.Total);
    }

    [Fact]
    public async Task CreateAsync_adds_then_saves()
    {
        var request = new CreateOrderRequest("Ada Lovelace", "Analytical Engine", 2, 10.50m);

        await _service.CreateAsync(request, CancellationToken.None);

        await _repository.Received(1).AddAsync(Arg.Any<Order>(), Arg.Any<CancellationToken>());
        await _repository.Received(1).SaveChangesAsync(Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task CreateAsync_does_not_save_when_the_domain_rejects_the_request()
    {
        var request = new CreateOrderRequest("Ada Lovelace", "Analytical Engine", 0, 10.50m);

        await Assert.ThrowsAsync<ArgumentOutOfRangeException>(
            () => _service.CreateAsync(request, CancellationToken.None));

        await _repository.DidNotReceive().SaveChangesAsync(Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task GetAsync_returns_null_when_the_order_is_unknown()
    {
        _repository.GetAsync(Arg.Any<Guid>(), Arg.Any<CancellationToken>()).Returns((Order?)null);

        var response = await _service.GetAsync(Guid.NewGuid(), CancellationToken.None);

        Assert.Null(response);
    }

    [Fact]
    public async Task GetAsync_maps_the_order_to_a_response()
    {
        var order = AnOrder();
        _repository.GetAsync(order.Id, Arg.Any<CancellationToken>()).Returns(order);

        var response = await _service.GetAsync(order.Id, CancellationToken.None);

        Assert.NotNull(response);
        Assert.Equal(order.Id, response.Id);
        Assert.Equal("Ada Lovelace", response.CustomerName);
        Assert.Equal(21.00m, response.Total);
    }

    [Fact]
    public async Task ListAsync_maps_every_order()
    {
        _repository.ListAsync(Arg.Any<CancellationToken>()).Returns([AnOrder(), AnOrder(3)]);

        var responses = await _service.ListAsync(CancellationToken.None);

        Assert.Equal(2, responses.Count);
        Assert.Equal([21.00m, 31.50m], responses.Select(r => r.Total));
    }

    [Fact]
    public async Task ConfirmAsync_saves_the_transition()
    {
        var order = AnOrder();
        _repository.GetAsync(order.Id, Arg.Any<CancellationToken>()).Returns(order);

        var response = await _service.ConfirmAsync(order.Id, CancellationToken.None);

        Assert.Equal(nameof(OrderStatus.Confirmed), response!.Status);
        await _repository.Received(1).SaveChangesAsync(Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task ConfirmAsync_returns_null_when_the_order_is_unknown()
    {
        _repository.GetAsync(Arg.Any<Guid>(), Arg.Any<CancellationToken>()).Returns((Order?)null);

        var response = await _service.ConfirmAsync(Guid.NewGuid(), CancellationToken.None);

        Assert.Null(response);
        await _repository.DidNotReceive().SaveChangesAsync(Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task ConfirmAsync_does_not_save_when_the_transition_is_rejected()
    {
        var order = AnOrder();
        order.Cancel();
        _repository.GetAsync(order.Id, Arg.Any<CancellationToken>()).Returns(order);

        await Assert.ThrowsAsync<InvalidOrderStateException>(
            () => _service.ConfirmAsync(order.Id, CancellationToken.None));

        await _repository.DidNotReceive().SaveChangesAsync(Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task ChangeQuantityAsync_updates_the_order()
    {
        var order = AnOrder();
        _repository.GetAsync(order.Id, Arg.Any<CancellationToken>()).Returns(order);

        var response = await _service.ChangeQuantityAsync(
            order.Id, new UpdateOrderQuantityRequest(4), CancellationToken.None);

        Assert.Equal(4, response!.Quantity);
        Assert.Equal(42.00m, response.Total);
    }

    [Fact]
    public async Task DeleteAsync_removes_and_saves_when_the_order_exists()
    {
        var order = AnOrder();
        _repository.GetAsync(order.Id, Arg.Any<CancellationToken>()).Returns(order);

        var deleted = await _service.DeleteAsync(order.Id, CancellationToken.None);

        Assert.True(deleted);
        await _repository.Received(1).RemoveAsync(order, Arg.Any<CancellationToken>());
        await _repository.Received(1).SaveChangesAsync(Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task DeleteAsync_reports_false_when_the_order_is_unknown()
    {
        _repository.GetAsync(Arg.Any<Guid>(), Arg.Any<CancellationToken>()).Returns((Order?)null);

        var deleted = await _service.DeleteAsync(Guid.NewGuid(), CancellationToken.None);

        Assert.False(deleted);
        await _repository.DidNotReceive().SaveChangesAsync(Arg.Any<CancellationToken>());
    }
}
