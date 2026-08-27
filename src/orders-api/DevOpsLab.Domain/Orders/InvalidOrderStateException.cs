namespace DevOpsLab.Domain.Orders;

/// <summary>
/// A state transition the order does not permit. Distinct from <see cref="ArgumentException"/>,
/// which signals bad input: the API maps this one to 409 Conflict and those to 400 Bad Request.
/// </summary>
public sealed class InvalidOrderStateException : Exception
{
    public InvalidOrderStateException(string message)
        : base(message)
    {
    }
}
