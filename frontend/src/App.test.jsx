/* global describe, it, expect, beforeEach, vi, global */
import { render, screen } from '@testing-library/react'
import App from './App'

describe('App', () => {
  beforeEach(() => {
    global.fetch = vi.fn((url) => {
      if (url.includes('/health')) {
        return Promise.resolve({
          ok: true,
          json: () => Promise.resolve({ status: 'healthy', database: 'connected' }),
        })
      }
      return Promise.resolve({
        ok: true,
        json: () => Promise.resolve({ products: [] }),
      })
    })
  })

  it('renders the dashboard title', async () => {
    render(<App />)
    expect(await screen.findByText('Cloud Platform')).toBeInTheDocument()
  })
})
