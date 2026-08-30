import { useCallback, useEffect, useState } from 'react'
import type { FormEvent } from 'react'
import { AuthenticatedTemplate, UnauthenticatedTemplate, useMsal } from '@azure/msal-react'
import { InteractionStatus } from '@azure/msal-browser'
import { loginRequest } from './authConfig'
import { BffError, createOrder, fetchOrders } from './ordersApi'
import type { OrderResponse } from './ordersApi'

/**
 * Turns a failure into the text the user sees.
 *
 * The 403 branch is the reason milestone M5 exists: the BFF answers 403 when the signed-in user
 * holds no app role (GET) or is not Orders.Admin (POST), and seeing that difference on screen is
 * the demonstration. Folding it into a generic "something went wrong" would erase the result.
 */
function describeError(error: unknown, action: string): string {
  if (error instanceof BffError && error.status === 403) {
    return `Your account is not permitted to ${action}.`
  }

  if (error instanceof BffError) {
    return `The BFF returned ${error.status}. ${error.message}`
  }

  if (error instanceof Error) {
    return error.message
  }

  return String(error)
}

function SignInBar() {
  const { instance, accounts, inProgress } = useMsal()

  // MsalProvider initialises the instance asynchronously and reports Startup while it does.
  // loginRedirect on an instance that has not finished initialising throws
  // BrowserAuthError: uninitialized_public_client_application, so the button waits it out.
  const busy = inProgress !== InteractionStatus.None

  return (
    <p>
      <AuthenticatedTemplate>
        {/* `name` is the profile's display name and is absent for accounts that never got one,
            so the UPN in `username` is the fallback that is always there. */}
        Signed in as <strong>{accounts[0]?.name ?? accounts[0]?.username}</strong>{' '}
        <button disabled={busy} onClick={() => void instance.logoutRedirect()}>
          Sign out
        </button>
      </AuthenticatedTemplate>
      <UnauthenticatedTemplate>
        <button disabled={busy} onClick={() => void instance.loginRedirect(loginRequest)}>
          Sign in
        </button>
      </UnauthenticatedTemplate>
    </p>
  )
}

function Orders() {
  const { instance, accounts } = useMsal()

  // AuthenticatedTemplate only renders this component once MSAL holds an account.
  const account = accounts[0]

  const [orders, setOrders] = useState<OrderResponse[]>([])
  const [listError, setListError] = useState('')
  const [formError, setFormError] = useState('')

  // The four inputs are held as strings, including the two numeric ones, because an <input
  // type="number"> hands back "" while the user is mid-edit and Number("") is 0 — binding them to
  // numbers would make an emptied field read as a valid zero.
  const [customerName, setCustomerName] = useState('')
  const [product, setProduct] = useState('')
  const [quantity, setQuantity] = useState('1')
  const [unitPrice, setUnitPrice] = useState('0')

  const loadOrders = useCallback(async () => {
    setListError('')

    try {
      setOrders(await fetchOrders(instance, account))
    } catch (error) {
      setListError(describeError(error, 'read orders'))
    }
  }, [instance, account])

  useEffect(() => {
    void loadOrders()
  }, [loadOrders])

  async function submit(event: FormEvent) {
    event.preventDefault()
    setFormError('')

    try {
      await createOrder(instance, account, {
        customerName,
        product,
        quantity: Number(quantity),
        unitPrice: Number(unitPrice),
      })
    } catch (error) {
      setFormError(describeError(error, 'create orders'))
      return
    }

    setCustomerName('')
    setProduct('')
    setQuantity('1')
    setUnitPrice('0')
    await loadOrders()
  }

  return (
    <>
      <h2>New order</h2>
      <form onSubmit={submit}>
        <p>
          <label htmlFor="customerName">Customer</label>{' '}
          <input
            id="customerName"
            required
            value={customerName}
            onChange={(event) => setCustomerName(event.target.value)}
          />
        </p>
        <p>
          <label htmlFor="product">Product</label>{' '}
          <input
            id="product"
            required
            value={product}
            onChange={(event) => setProduct(event.target.value)}
          />
        </p>
        <p>
          <label htmlFor="quantity">Quantity</label>{' '}
          <input
            id="quantity"
            type="number"
            min="1"
            required
            value={quantity}
            onChange={(event) => setQuantity(event.target.value)}
          />
        </p>
        <p>
          <label htmlFor="unitPrice">Unit price</label>{' '}
          <input
            id="unitPrice"
            type="number"
            min="0"
            step="0.01"
            required
            value={unitPrice}
            onChange={(event) => setUnitPrice(event.target.value)}
          />
        </p>
        <p>
          <button type="submit">Create order</button>
        </p>
      </form>

      {formError && <p role="alert">{formError}</p>}

      <h2>Orders</h2>
      <p>
        <button onClick={() => void loadOrders()}>Refresh</button>
      </p>

      {listError && <p role="alert">{listError}</p>}

      <table border={1} cellPadding={4}>
        <thead>
          <tr>
            <th>Customer</th>
            <th>Product</th>
            <th>Quantity</th>
            <th>Unit price</th>
            <th>Total</th>
            <th>Status</th>
          </tr>
        </thead>
        <tbody>
          {orders.map((order) => (
            <tr key={order.id}>
              <td>{order.customerName}</td>
              <td>{order.product}</td>
              <td>{order.quantity}</td>
              <td>{order.unitPrice}</td>
              <td>{order.total}</td>
              <td>{order.status}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </>
  )
}

export default function App() {
  return (
    <main style={{ fontFamily: 'sans-serif', margin: '2rem' }}>
      <h1>Orders</h1>
      <SignInBar />
      <UnauthenticatedTemplate>
        <p>Sign in to read and create orders.</p>
      </UnauthenticatedTemplate>
      <AuthenticatedTemplate>
        <Orders />
      </AuthenticatedTemplate>
    </main>
  )
}
