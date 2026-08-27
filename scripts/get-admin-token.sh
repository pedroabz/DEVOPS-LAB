#!/usr/bin/env bash
# Prints an access token for calling the Orders API directly, bypassing the BFF.
#
# Works because of two things in iac/modules/entraApps.bicep: the API exposes a
# `user_impersonation` delegated scope (without one there is nothing for a human to request), and
# it pre-authorises the Azure CLI's client ID (without that you hit a consent wall).
#
# Ordinary users cannot do this. The only reason it works is an explicit Orders.Admin.Direct
# app role assignment.
#
#   ./scripts/get-admin-token.sh                       # print the token
#   TOKEN=$(./scripts/get-admin-token.sh); curl -H "Authorization: Bearer $TOKEN" ...

set -euo pipefail

TENANT_ID=$(az account show --query tenantId -o tsv)

# --scope, not --resource: the app registration requests v2 tokens.
az account get-access-token \
  --scope "api://${TENANT_ID}/orders-api/user_impersonation" \
  --query accessToken -o tsv
