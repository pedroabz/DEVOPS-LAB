using System.ComponentModel.DataAnnotations;

namespace DevOpsLab.Application.Orders;

public sealed record CreateOrderRequest(
    [Required, StringLength(200)] string CustomerName,
    [Required, StringLength(200)] string Product,
    [Range(1, int.MaxValue)] int Quantity,
    [Range(0, double.MaxValue)] decimal UnitPrice);

public sealed record UpdateOrderQuantityRequest(
    [Range(1, int.MaxValue)] int Quantity);

public sealed record OrderResponse(
    Guid Id,
    string CustomerName,
    string Product,
    int Quantity,
    decimal UnitPrice,
    decimal Total,
    string Status,
    DateTimeOffset CreatedAt);
