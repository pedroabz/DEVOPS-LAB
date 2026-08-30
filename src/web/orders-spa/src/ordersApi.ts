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
    // consent, an expired session, an MFA prompt. Prompting on any other error would send the user
    // to Entra for something they cannot resolve there, and bury the real cause on the way.
    if (error instanceof InteractionRequiredAuthError) {
      // Unlike acquireTokenPopup this never returns a token: it navigates the whole page to Entra,
      // and the token arrives on the way back in, through MsalProvider's handleRedirectPromise.
      // Whatever called this function is discarded along with the page.
      await msal.acquireTokenRedirect({ scopes: [bffScope], account })
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
