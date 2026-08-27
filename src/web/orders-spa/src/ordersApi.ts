import { InteractionRequiredAuthError } from '@azure/msal-browser'
import type { AccountInfo, IPublicClientApplication } from '@azure/msal-browser'
import { bffBaseUrl, bffScope } from './authConfig'

// Mirrors OrderResponse in src/application/DevOpsLab.Application/Orders/OrderDtos.cs. The BFF
// forwards the API's bodies unchanged, so any drift here is a drift from the API's contract.
export type OrderResponse = {
  id: string
  customerName: string
  product: string
  quantity: number
  unitPrice: number
  total: number
  status: string
  createdAt: string
}

// Mirrors CreateOrderRequest in the same file.
export type CreateOrderRequest = {
  customerName: string
  product: string
  quantity: number
  unitPrice: number
}

/**
 * Carries the HTTP status alongside the message, because the UI has to tell a 403 apart from every
 * other failure — a 403 is a policy decision worth spelling out, the rest are just errors.
 */
export class BffError extends Error {
  readonly status: number

  constructor(status: number, message: string) {
    super(message)
    this.status = status
  }
}

async function acquireBffToken(
  msal: IPublicClientApplication,
  account: AccountInfo,
): Promise<string> {
  try {
    const result = await msal.acquireTokenSilent({ scopes: [bffScope], account })
    return result.accessToken
  } catch (error) {
    // Only InteractionRequiredAuthError means "the user can fix this by being asked" — missing
    // consent, an expired session, an MFA prompt. Prompting on any other error would open a popup
    // the user cannot resolve and would bury the real cause behind a second sign-in attempt.
    if (error instanceof InteractionRequiredAuthError) {
      const result = await msal.acquireTokenPopup({ scopes: [bffScope], account })
      return result.accessToken
    }

    throw error
  }
}

export async function fetchOrders(
  msal: IPublicClientApplication,
  account: AccountInfo,
): Promise<OrderResponse[]> {
  const token = await acquireBffToken(msal, account)

  const response = await fetch(`${bffBaseUrl}/api/orders`, {
    headers: { Authorization: `Bearer ${token}` },
  })

  if (!response.ok) {
    throw new BffError(response.status, await response.text())
  }

  return response.json()
}

export async function createOrder(
  msal: IPublicClientApplication,
  account: AccountInfo,
  order: CreateOrderRequest,
): Promise<OrderResponse> {
  const token = await acquireBffToken(msal, account)

  const response = await fetch(`${bffBaseUrl}/api/orders`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(order),
  })

  if (!response.ok) {
    throw new BffError(response.status, await response.text())
  }

  return response.json()
}
