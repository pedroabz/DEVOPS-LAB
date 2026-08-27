#!/usr/bin/env bash
# Removes everything v2 created in Entra ID.
#
# `az group delete` removes NONE of this — Entra objects are tenant-scoped, not resource-group
# scoped. Without this script they accumulate silently across teardown/rebuild cycles.
#
# The purge step is not optional. Soft-deleted app registrations keep their uniqueName AND their
# identifierUris for 30 days, so a rebuild fails with "Another object with the same value for
# property uniqueName already exists". Same shape as the Key Vault tombstone problem.

set -euo pipefail

UNIQUE_NAMES=(devopslab-api-dev devopslab-bff-dev devopslab-spa-dev)

for unique in "${UNIQUE_NAMES[@]}"; do
  APP_ID=$(az ad app list --filter "uniqueName eq '${unique}'" --query "[0].appId" -o tsv 2>/dev/null || true)
  if [[ -z "$APP_ID" ]]; then
    echo "not found: $unique"
    continue
  fi

  # Delete the service principal explicitly rather than relying on a cascade — whether deleting
  # an application also removes its service principal is not documented either way.
  SP_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv 2>/dev/null || true)
  if [[ -n "$SP_ID" ]]; then
    az ad sp delete --id "$APP_ID" && echo "deleted sp: $unique"
  fi

  OBJECT_ID=$(az ad app show --id "$APP_ID" --query id -o tsv)
  az ad app delete --id "$APP_ID" && echo "deleted app: $unique"

  az rest --method DELETE \
    --url "https://graph.microsoft.com/v1.0/directory/deletedItems/${OBJECT_ID}" \
    && echo "purged tombstone: $unique"
done

echo
echo "Test users are left alone on purpose — they take no name that a rebuild needs, and"
echo "recreating them means re-registering MFA. Remove them by hand if you actually want to:"
echo "  az ad user delete --id ana.reader@<domain>"
