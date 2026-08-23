using DevOpsLab.Domain.Orders;
using Microsoft.EntityFrameworkCore;

namespace DevOpsLab.Infrastructure.Persistence;

public sealed class OrdersDbContext : DbContext
{
    public OrdersDbContext(DbContextOptions<OrdersDbContext> options)
        : base(options)
    {
    }

    public DbSet<Order> Orders => Set<Order>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        var order = modelBuilder.Entity<Order>();

        order.ToTable("Orders");
        order.HasKey(o => o.Id);

        order.Property(o => o.CustomerName)
            .IsRequired()
            .HasMaxLength(Order.MaxCustomerNameLength);

        order.Property(o => o.Product)
            .IsRequired()
            .HasMaxLength(Order.MaxProductLength);

        // decimal defaults to (18,2) in SQL Server, but stating it means a provider change or an EF
        // default change cannot silently alter how money is stored.
        order.Property(o => o.UnitPrice)
            .HasPrecision(18, 2);

        // Stored as its int value. The string name would be friendlier to read in SSMS but makes
        // renaming a member a data migration.
        order.Property(o => o.Status)
            .IsRequired();

        order.Property(o => o.CreatedAt)
            .IsRequired();

        // Total is computed from Quantity and UnitPrice, so there is nothing to store.
        order.Ignore(o => o.Total);

        // The list endpoint returns newest first; without this every list is a full scan and sort.
        order.HasIndex(o => o.CreatedAt);
    }
}
