#!/usr/bin/env bash
# Creates the two test users that prove Orders.Reader and Orders.Admin behave differently.
#
# This is the ONE part of v2 that cannot be Bicep. The Microsoft Graph Bicep extension has a
# `users` type, but it is read-only — `existing` is the only legal form. Their app ROLE
# ASSIGNMENTS are Bicep, in iac/modules/entraAssignments.bicep.
#
# Run once, from your own az login session. Then paste the printed object IDs into
# iac/subscription.dev.bicepparam.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [[ ! -f .env ]]; then
  echo "No .env found. Copy .env.example to .env and set the two passwords." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

: "${TEST_USER_READER_PASSWORD:?not set in .env}"
: "${TEST_USER_ADMIN_PASSWORD:?not set in .env}"

DOMAIN=$(az rest --method get --url "https://graph.microsoft.com/v1.0/domains" \
  --query "value[?isDefault].id | [0]" -o tsv)
echo "Tenant domain: $DOMAIN"

create_user () {
  local display="$1" nickname="$2" password="$3"
  local upn="${nickname}@${DOMAIN}"

  if az ad user show --id "$upn" >/dev/null 2>&1; then
    echo "  exists: $upn" >&2
  else
    # --force-change-password-next-sign-in defaults to true, and a forced password change
    # inside an MSAL popup is a miserable first experience for a demo.
    az ad user create \
      --display-name "$display" \
      --user-principal-name "$upn" \
      --password "$password" \
      --force-change-password-next-sign-in false \
      --output none
    echo "  created: $upn" >&2
  fi

  az ad user show --id "$upn" --query id -o tsv
}

echo "=== Orders.Reader ==="
READER_ID=$(create_user "Ana Reader" "ana.reader" "$TEST_USER_READER_PASSWORD")
echo "=== Orders.Admin ==="
ADMIN_ID=$(create_user "Miguel Admin" "miguel.admin" "$TEST_USER_ADMIN_PASSWORD")

cat <<EOF

Paste these into iac/subscription.dev.bicepparam:

  param readerTestUserObjectId = '${READER_ID}'
  param adminTestUserObjectId  = '${ADMIN_ID}'

Then, BEFORE trying the RBAC demo: sign in as each user once in a private browser window and
complete MFA registration. Entra security defaults force it on first interactive sign-in, and it
will otherwise stop the demo dead at the point you least expect it. Do not disable security
defaults; the Conditional Access exclusion that would avoid this needs Entra ID P1.
EOF
