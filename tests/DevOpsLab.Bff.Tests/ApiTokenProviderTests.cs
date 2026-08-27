using Azure.Core;
using DevOpsLab.Bff.Orders;
using Microsoft.Extensions.Time.Testing;
using NSubstitute;

namespace DevOpsLab.Bff.Tests;

public sealed class ApiTokenProviderTests
{
    private static readonly DateTimeOffset Now = new(2026, 8, 25, 12, 0, 0, TimeSpan.Zero);
    private const string Scope = "api://example/orders-api/.default";

    private static ApiTokenProvider AProvider(TokenCredential credential, TimeProvider time)
        => new(credential, time, Scope);

    private static TokenCredential ACredentialReturning(params AccessToken[] tokens)
    {
        var credential = Substitute.For<TokenCredential>();
        var queue = new Queue<AccessToken>(tokens);
        credential
            .GetTokenAsync(Arg.Any<TokenRequestContext>(), Arg.Any<CancellationToken>())
            .Returns(_ => new ValueTask<AccessToken>(queue.Dequeue()));
        return credential;
    }

    [Fact]
    public async Task Reuses_the_cached_token_while_it_is_not_near_expiry()
    {
        var time = new FakeTimeProvider(Now);
        var credential = ACredentialReturning(new AccessToken("first", Now.AddHours(1)));
        var provider = AProvider(credential, time);

        var one = await provider.GetTokenAsync(CancellationToken.None);
        var two = await provider.GetTokenAsync(CancellationToken.None);

        Assert.Equal("first", one);
        Assert.Equal("first", two);
        await credential.Received(1).GetTokenAsync(Arg.Any<TokenRequestContext>(), Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task Refreshes_once_the_token_is_inside_the_five_minute_skew()
    {
        var time = new FakeTimeProvider(Now);
        var credential = ACredentialReturning(
            new AccessToken("first", Now.AddMinutes(10)),
            new AccessToken("second", Now.AddHours(1)));
        var provider = AProvider(credential, time);

        var before = await provider.GetTokenAsync(CancellationToken.None);

        // Six minutes on, the token has four minutes left — inside the skew, so it must not be
        // handed out even though it has not technically expired.
        time.Advance(TimeSpan.FromMinutes(6));
        var after = await provider.GetTokenAsync(CancellationToken.None);

        Assert.Equal("first", before);
        Assert.Equal("second", after);
    }

    [Fact]
    public async Task Requests_only_one_token_when_several_callers_arrive_at_once()
    {
        var time = new FakeTimeProvider(Now);
        var credential = ACredentialReturning(new AccessToken("only", Now.AddHours(1)));
        var provider = AProvider(credential, time);

        var results = await Task.WhenAll(
            Enumerable.Range(0, 8).Select(_ => provider.GetTokenAsync(CancellationToken.None)));

        Assert.All(results, token => Assert.Equal("only", token));

        // The double-check inside the lock is what makes this one rather than eight. Eight would
        // be wasted throttle budget on every cold start.
        await credential.Received(1).GetTokenAsync(Arg.Any<TokenRequestContext>(), Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task Requests_a_token_for_the_configured_scope()
    {
        var time = new FakeTimeProvider(Now);
        var credential = ACredentialReturning(new AccessToken("t", Now.AddHours(1)));
        var provider = AProvider(credential, time);

        await provider.GetTokenAsync(CancellationToken.None);

        await credential.Received(1).GetTokenAsync(
            Arg.Is<TokenRequestContext>(context => context.Scopes.Single() == Scope),
            Arg.Any<CancellationToken>());
    }
}
