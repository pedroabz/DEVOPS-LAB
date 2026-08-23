using DevOpsLab.Application.Orders;
using DevOpsLab.Domain.Orders;
using Microsoft.EntityFrameworkCore;

namespace DevOpsLab.Infrastructure.Persistence;

internal sealed class OrderRepository : IOrderRepository
{
    private readonly OrdersDbContext _dbContext;

    public OrderRepository(OrdersDbContext dbContext)
    {
        _dbContext = dbContext;
    }

    public async Task<IReadOnlyList<Order>> ListAsync(CancellationToken cancellationToken)
        => await _dbContext.Orders
            .AsNoTracking()
            .OrderByDescending(o => o.CreatedAt)
            .ToListAsync(cancellationToken);

    // Tracked, unlike ListAsync: callers load an order here in order to mutate it and save.
    public async Task<Order?> GetAsync(Guid id, CancellationToken cancellationToken)
        => await _dbContext.Orders.FirstOrDefaultAsync(o => o.Id == id, cancellationToken);

    public async Task AddAsync(Order order, CancellationToken cancellationToken)
        => await _dbContext.Orders.AddAsync(order, cancellationToken);

    public Task RemoveAsync(Order order, CancellationToken cancellationToken)
    {
        _dbContext.Orders.Remove(order);
        return Task.CompletedTask;
    }

    public Task SaveChangesAsync(CancellationToken cancellationToken)
        => _dbContext.SaveChangesAsync(cancellationToken);
}
