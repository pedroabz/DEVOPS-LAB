#!/usr/bin/env bash
# Deploy (or preview) the dev environment.
#
#   ./scripts/deploy-dev.sh            # what-if — shows changes, deploys nothing
#   ./scripts/deploy-dev.sh deploy     # actually deploys
#
# Exists because subscription.dev.bicepparam reads CLIENT_IP from the environment,
# and `az` does not load .env on its own.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

TEMPLATE="iac/main.bicep"
PARAMS="iac/subscription.dev.bicepparam"
LOCATION="northeurope"   # where the deployment RECORD is stored, not where resources go
NAME="devopslab-dev"

if [[ ! -f .env ]]; then
  echo "No .env found. Copy .env.example to .env and fill it in:" >&2
  echo "  cp .env.example .env" >&2
  echo "  curl https://api.ipify.org   # your CLIENT_IP" >&2
  exit 1
fi

# set -a exports everything defined until set +a, which is what makes these visible
# to az and therefore to readEnvironmentVariable() in the .bicepparam file.
set -a
# shellcheck disable=SC1091
source .env
set +a

: "${CLIENT_IP:?CLIENT_IP is not set in .env}"

echo "Subscription : $(az account show --query name -o tsv)"
echo "Client IP    : ${CLIENT_IP}"
echo

if [[ "${1:-what-if}" == "deploy" ]]; then
  echo "Deploying. This creates billable resources."
  az deployment sub create \
    --location "$LOCATION" \
    --name "$NAME" \
    --template-file "$TEMPLATE" \
    --parameters "$PARAMS"
else
  echo "Previewing (what-if). Nothing will be created."
  az deployment sub what-if \
    --location "$LOCATION" \
    --name "$NAME" \
    --template-file "$TEMPLATE" \
    --parameters "$PARAMS" \
    --result-format ResourceIdOnly
  echo
  echo "To apply: ./scripts/deploy-dev.sh deploy"
fi
