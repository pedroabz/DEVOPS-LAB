namespace DevOpsLab.Bff.Orders;

/// <summary>
/// Mirrors the Orders API's own contract. Deliberately redeclared rather than shared via a project
/// reference: the BFF and the API deploy independently, and a compile-time coupling between them
/// would mean neither could change shape without the other.
/// </summary>
public sealed record OrderResponse(
    Guid Id,
    string CustomerName,
    string Product,
    int Quantity,
    decimal UnitPrice,
    decimal Total,
    string Status,
    DateTimeOffset CreatedAt);

public sealed record CreateOrderRequest(
    string CustomerName,
    string Product,
    int Quantity,
    decimal UnitPrice);
