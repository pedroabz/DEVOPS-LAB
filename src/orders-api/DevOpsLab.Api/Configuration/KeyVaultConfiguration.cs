using Azure.Identity;

namespace DevOpsLab.Api.Configuration;

public static class KeyVaultConfiguration
{
    /// <summary>
    /// Configuration key holding the vault URI, e.g. https://kv-dvlab-dev-xxxx.vault.azure.net/.
    /// </summary>
    public const string VaultUriKey = "KeyVault:Uri";

    /// <summary>
    /// Layers Key Vault secrets over the existing configuration when a vault URI is present, and
    /// does nothing when it is not.
    /// </summary>
    /// <remarks>
    /// No vault exists yet (v0-foundations.md task 6.1), and nothing supplies <see cref="VaultUriKey"/>,
    /// so today this is a no-op. It is wired now so that adding the vault and the app setting is the
    /// only change required later. Authentication is <see cref="DefaultAzureCredential"/>: the Web
    /// App's system-assigned managed identity in Azure, your <c>az login</c> session locally.
    /// </remarks>
    public static void AddKeyVaultIfConfigured(this IConfigurationBuilder configuration, ILogger logger)
    {
        var vaultUri = configuration.Build()[VaultUriKey];

        if (string.IsNullOrWhiteSpace(vaultUri))
        {
            logger.LogInformation(
                "No {Key} configured; skipping the Key Vault configuration provider.", VaultUriKey);
            return;
        }

        configuration.AddAzureKeyVault(new Uri(vaultUri), new DefaultAzureCredential());
        logger.LogInformation("Key Vault configuration provider added for {VaultUri}.", vaultUri);
    }
}
