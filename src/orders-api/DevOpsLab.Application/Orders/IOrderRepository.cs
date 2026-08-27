using DevOpsLab.Domain.Orders;

namespace DevOpsLab.Application.Orders;

/// <summary>
/// Declared here rather than in Infrastructure so the dependency points inwards: Application owns
/// the contract, Infrastructure implements it.
/// </summary>
public interface IOrderRepository
{
    Task<IReadOnlyList<Order>> ListAsync(CancellationToken cancellationToken);

    Task<Order?> GetAsync(Guid id, CancellationToken cancellationToken);

    Task AddAsync(Order order, CancellationToken cancellationToken);

    Task RemoveAsync(Order order, CancellationToken cancellationToken);

    /// <summary>
    /// Persists changes tracked against orders already loaded by this repository.
    /// </summary>
    Task SaveChangesAsync(CancellationToken cancellationToken);
}
