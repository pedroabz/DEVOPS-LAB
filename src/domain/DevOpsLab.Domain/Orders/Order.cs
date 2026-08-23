namespace DevOpsLab.Domain.Orders;

/// <summary>
/// An order for a quantity of a single product.
/// </summary>
public sealed class Order
{
    public const int MaxCustomerNameLength = 200;
    public const int MaxProductLength = 200;

    // EF Core materialises entities through this constructor, bypassing Create and its guards.
    // That is intentional: rows already in the database were validated on the way in.
    private Order()
    {
        CustomerName = string.Empty;
        Product = string.Empty;
    }

    public Guid Id { get; private set; }

    public string CustomerName { get; private set; }

    public string Product { get; private set; }

    public int Quantity { get; private set; }

    public decimal UnitPrice { get; private set; }

    public OrderStatus Status { get; private set; }

    public DateTimeOffset CreatedAt { get; private set; }

    /// <summary>
    /// Not persisted — recomputed on read so a price correction can never leave a stale total behind.
    /// </summary>
    public decimal Total => Quantity * UnitPrice;

    /// <param name="now">
    /// Passed in rather than read from the clock so tests are deterministic and the caller owns the
    /// time source.
    /// </param>
    public static Order Create(
        string customerName,
        string product,
        int quantity,
        decimal unitPrice,
        DateTimeOffset now)
    {
        ValidateCustomerName(customerName);
        ValidateProduct(product);
        ValidateQuantity(quantity);
        ValidateUnitPrice(unitPrice);

        return new Order
        {
            Id = Guid.CreateVersion7(),
            CustomerName = customerName.Trim(),
            Product = product.Trim(),
            Quantity = quantity,
            UnitPrice = unitPrice,
            Status = OrderStatus.Pending,
            CreatedAt = now
        };
    }

    public void Confirm()
    {
        if (Status != OrderStatus.Pending)
        {
            throw new InvalidOrderStateException($"Only a pending order can be confirmed. This one is {Status}.");
        }

        Status = OrderStatus.Confirmed;
    }

    public void Ship()
    {
        if (Status != OrderStatus.Confirmed)
        {
            throw new InvalidOrderStateException($"Only a confirmed order can be shipped. This one is {Status}.");
        }

        Status = OrderStatus.Shipped;
    }

    public void Cancel()
    {
        if (Status == OrderStatus.Shipped)
        {
            throw new InvalidOrderStateException("A shipped order cannot be cancelled.");
        }

        if (Status == OrderStatus.Cancelled)
        {
            throw new InvalidOrderStateException("The order is already cancelled.");
        }

        Status = OrderStatus.Cancelled;
    }

    public void ChangeQuantity(int quantity)
    {
        if (Status != OrderStatus.Pending)
        {
            throw new InvalidOrderStateException($"Quantity is fixed once an order leaves Pending. This one is {Status}.");
        }

        ValidateQuantity(quantity);
        Quantity = quantity;
    }

    private static void ValidateCustomerName(string customerName)
    {
        if (string.IsNullOrWhiteSpace(customerName))
        {
            throw new ArgumentException("Customer name is required.", nameof(customerName));
        }

        if (customerName.Trim().Length > MaxCustomerNameLength)
        {
            throw new ArgumentException(
                $"Customer name cannot exceed {MaxCustomerNameLength} characters.",
                nameof(customerName));
        }
    }

    private static void ValidateProduct(string product)
    {
        if (string.IsNullOrWhiteSpace(product))
        {
            throw new ArgumentException("Product is required.", nameof(product));
        }

        if (product.Trim().Length > MaxProductLength)
        {
            throw new ArgumentException(
                $"Product cannot exceed {MaxProductLength} characters.",
                nameof(product));
        }
    }

    private static void ValidateQuantity(int quantity)
    {
        if (quantity <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(quantity), quantity, "Quantity must be greater than zero.");
        }
    }

    private static void ValidateUnitPrice(decimal unitPrice)
    {
        if (unitPrice < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(unitPrice), unitPrice, "Unit price cannot be negative.");
        }
    }
}
