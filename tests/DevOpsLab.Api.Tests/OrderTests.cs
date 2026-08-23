using DevOpsLab.Domain.Orders;

namespace DevOpsLab.Api.Tests;

public sealed class OrderTests
{
    private static readonly DateTimeOffset Now = new(2026, 8, 23, 12, 0, 0, TimeSpan.Zero);

    private static Order APendingOrder() => Order.Create("Ada Lovelace", "Analytical Engine", 2, 10.50m, Now);

    [Fact]
    public void Create_starts_the_order_pending()
    {
        var order = APendingOrder();

        Assert.Equal(OrderStatus.Pending, order.Status);
        Assert.Equal(Now, order.CreatedAt);
        Assert.NotEqual(Guid.Empty, order.Id);
    }

    [Fact]
    public void Create_trims_the_text_fields()
    {
        var order = Order.Create("  Ada  ", "  Engine  ", 1, 1m, Now);

        Assert.Equal("Ada", order.CustomerName);
        Assert.Equal("Engine", order.Product);
    }

    [Fact]
    public void Total_multiplies_quantity_by_unit_price()
    {
        var order = Order.Create("Ada", "Engine", 3, 9.99m, Now);

        Assert.Equal(29.97m, order.Total);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void Create_rejects_a_blank_customer_name(string customerName)
    {
        Assert.Throws<ArgumentException>(() => Order.Create(customerName, "Engine", 1, 1m, Now));
    }

    [Fact]
    public void Create_rejects_a_customer_name_over_the_limit()
    {
        var tooLong = new string('a', Order.MaxCustomerNameLength + 1);

        Assert.Throws<ArgumentException>(() => Order.Create(tooLong, "Engine", 1, 1m, Now));
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    public void Create_rejects_a_non_positive_quantity(int quantity)
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => Order.Create("Ada", "Engine", quantity, 1m, Now));
    }

    [Fact]
    public void Create_rejects_a_negative_unit_price()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => Order.Create("Ada", "Engine", 1, -0.01m, Now));
    }

    [Fact]
    public void Create_allows_a_zero_unit_price()
    {
        var order = Order.Create("Ada", "Engine", 1, 0m, Now);

        Assert.Equal(0m, order.Total);
    }

    [Fact]
    public void Confirm_moves_a_pending_order_to_confirmed()
    {
        var order = APendingOrder();

        order.Confirm();

        Assert.Equal(OrderStatus.Confirmed, order.Status);
    }

    [Fact]
    public void Confirm_is_rejected_when_the_order_is_not_pending()
    {
        var order = APendingOrder();
        order.Confirm();

        Assert.Throws<InvalidOrderStateException>(order.Confirm);
    }

    [Fact]
    public void Ship_requires_the_order_to_be_confirmed_first()
    {
        var order = APendingOrder();

        Assert.Throws<InvalidOrderStateException>(order.Ship);
    }

    [Fact]
    public void Ship_moves_a_confirmed_order_to_shipped()
    {
        var order = APendingOrder();
        order.Confirm();

        order.Ship();

        Assert.Equal(OrderStatus.Shipped, order.Status);
    }

    [Fact]
    public void Cancel_is_allowed_from_confirmed()
    {
        var order = APendingOrder();
        order.Confirm();

        order.Cancel();

        Assert.Equal(OrderStatus.Cancelled, order.Status);
    }

    [Fact]
    public void Cancel_is_rejected_once_the_order_has_shipped()
    {
        var order = APendingOrder();
        order.Confirm();
        order.Ship();

        Assert.Throws<InvalidOrderStateException>(order.Cancel);
    }

    [Fact]
    public void Cancel_is_rejected_when_already_cancelled()
    {
        var order = APendingOrder();
        order.Cancel();

        Assert.Throws<InvalidOrderStateException>(order.Cancel);
    }

    [Fact]
    public void ChangeQuantity_updates_a_pending_order()
    {
        var order = APendingOrder();

        order.ChangeQuantity(5);

        Assert.Equal(5, order.Quantity);
        Assert.Equal(52.50m, order.Total);
    }

    [Fact]
    public void ChangeQuantity_is_rejected_once_the_order_leaves_pending()
    {
        var order = APendingOrder();
        order.Confirm();

        Assert.Throws<InvalidOrderStateException>(() => order.ChangeQuantity(5));
    }

    [Fact]
    public void ChangeQuantity_still_rejects_a_non_positive_quantity()
    {
        var order = APendingOrder();

        Assert.Throws<ArgumentOutOfRangeException>(() => order.ChangeQuantity(0));
    }
}
