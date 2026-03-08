import { useState, useEffect } from 'react'

const API_URL = import.meta.env.VITE_API_URL || ''

function App() {
  const [products, setProducts] = useState([])
  const [health, setHealth] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState({ name: '', description: '', price: '', category: '' })

  useEffect(() => {
    fetchProducts()
    fetchHealth()
    const interval = setInterval(fetchHealth, 30000)
    return () => clearInterval(interval)
  }, [])

  async function fetchProducts() {
    try {
      setLoading(true)
      const res = await fetch(`${API_URL}/api/products`)
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const data = await res.json()
      setProducts(data.products)
      setError(null)
    } catch (err) {
      setError('Failed to load products. Is the API running?')
    } finally {
      setLoading(false)
    }
  }

  async function fetchHealth() {
    try {
      const res = await fetch(`${API_URL}/health`)
      const data = await res.json()
      setHealth(data)
    } catch {
      setHealth({ status: 'unreachable', database: 'unknown' })
    }
  }

  async function handleSubmit(e) {
    e.preventDefault()
    try {
      const res = await fetch(`${API_URL}/api/products`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ...form, price: parseFloat(form.price) }),
      })
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      setForm({ name: '', description: '', price: '', category: '' })
      setShowForm(false)
      fetchProducts()
    } catch (err) {
      setError('Failed to create product')
    }
  }

  async function handleDelete(id) {
    try {
      await fetch(`${API_URL}/api/products/${id}`, { method: 'DELETE' })
      fetchProducts()
    } catch (err) {
      setError('Failed to delete product')
    }
  }

  return (
    <div className="min-h-screen bg-slate-900">
      {/* Header */}
      <header className="bg-slate-800 border-b border-slate-700 shadow-lg">
        <div className="max-w-7xl mx-auto px-4 py-4 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 bg-blue-600 rounded-lg flex items-center justify-center text-white font-bold text-lg">
              CP
            </div>
            <div>
              <h1 className="text-xl font-bold text-white">Cloud Platform</h1>
              <p className="text-xs text-slate-400">AKS Microservices Dashboard</p>
            </div>
          </div>
          <div className="flex items-center gap-4">
            {health && (
              <div className="flex items-center gap-2 text-sm">
                <div className={`w-2.5 h-2.5 rounded-full ${
                  health.status === 'healthy' ? 'bg-green-500 animate-pulse' :
                  health.status === 'degraded' ? 'bg-yellow-500' : 'bg-red-500'
                }`} />
                <span className="text-slate-300">
                  API: {health.status} | DB: {health.database}
                </span>
              </div>
            )}
          </div>
        </div>
      </header>

      <main className="max-w-7xl mx-auto px-4 py-8">
        {/* Stats Cards */}
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-8">
          <StatCard title="Total Products" value={products.length} color="blue" />
          <StatCard title="In Stock" value={products.filter(p => p.in_stock).length} color="green" />
          <StatCard title="Out of Stock" value={products.filter(p => !p.in_stock).length} color="red" />
          <StatCard title="Categories" value={[...new Set(products.map(p => p.category))].length} color="purple" />
        </div>

        {/* Actions */}
        <div className="flex items-center justify-between mb-6">
          <h2 className="text-lg font-semibold text-white">Product Catalog</h2>
          <div className="flex gap-2">
            <button onClick={fetchProducts}
              className="px-4 py-2 bg-slate-700 text-slate-200 rounded-lg hover:bg-slate-600 transition text-sm">
              Refresh
            </button>
            <button onClick={() => setShowForm(!showForm)}
              className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition text-sm">
              {showForm ? 'Cancel' : '+ Add Product'}
            </button>
          </div>
        </div>

        {error && (
          <div className="mb-4 p-3 bg-red-900/50 border border-red-700 rounded-lg text-red-200 text-sm">
            {error}
            <button onClick={() => setError(null)} className="ml-2 underline">Dismiss</button>
          </div>
        )}

        {/* Create Form */}
        {showForm && (
          <form onSubmit={handleSubmit} className="mb-6 p-4 bg-slate-800 rounded-lg border border-slate-700">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <input type="text" placeholder="Product Name" required value={form.name}
                onChange={e => setForm({ ...form, name: e.target.value })}
                className="px-3 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white placeholder-slate-400" />
              <input type="text" placeholder="Category" value={form.category}
                onChange={e => setForm({ ...form, category: e.target.value })}
                className="px-3 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white placeholder-slate-400" />
              <input type="number" step="0.01" placeholder="Price" required value={form.price}
                onChange={e => setForm({ ...form, price: e.target.value })}
                className="px-3 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white placeholder-slate-400" />
              <input type="text" placeholder="Description" value={form.description}
                onChange={e => setForm({ ...form, description: e.target.value })}
                className="px-3 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white placeholder-slate-400" />
            </div>
            <button type="submit" className="mt-4 px-6 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700 transition">
              Create Product
            </button>
          </form>
        )}

        {/* Product Table */}
        {loading ? (
          <div className="text-center py-12 text-slate-400">Loading...</div>
        ) : products.length === 0 ? (
          <div className="text-center py-12 text-slate-400">No products found</div>
        ) : (
          <div className="overflow-x-auto rounded-lg border border-slate-700">
            <table className="w-full">
              <thead className="bg-slate-800">
                <tr>
                  <th className="px-4 py-3 text-left text-xs font-medium text-slate-400 uppercase">ID</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-slate-400 uppercase">Name</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-slate-400 uppercase">Category</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-slate-400 uppercase">Price</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-slate-400 uppercase">Status</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-slate-400 uppercase">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-700">
                {products.map(product => (
                  <tr key={product.id} className="hover:bg-slate-800/50 transition">
                    <td className="px-4 py-3 text-sm text-slate-300">#{product.id}</td>
                    <td className="px-4 py-3">
                      <div className="text-sm font-medium text-white">{product.name}</div>
                      {product.description && (
                        <div className="text-xs text-slate-400 mt-0.5">{product.description}</div>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      <span className="px-2 py-1 text-xs bg-slate-700 text-slate-300 rounded-full">
                        {product.category || 'Uncategorized'}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-sm text-slate-300 font-mono">
                      ${parseFloat(product.price).toFixed(2)}
                    </td>
                    <td className="px-4 py-3">
                      <span className={`px-2 py-1 text-xs rounded-full ${
                        product.in_stock
                          ? 'bg-green-900/50 text-green-300 border border-green-700'
                          : 'bg-red-900/50 text-red-300 border border-red-700'
                      }`}>
                        {product.in_stock ? 'In Stock' : 'Out of Stock'}
                      </span>
                    </td>
                    <td className="px-4 py-3">
                      <button onClick={() => handleDelete(product.id)}
                        className="text-xs text-red-400 hover:text-red-300 transition">
                        Delete
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {/* Footer Info */}
        <div className="mt-8 p-4 bg-slate-800 rounded-lg border border-slate-700">
          <h3 className="text-sm font-semibold text-slate-300 mb-2">System Info</h3>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-xs text-slate-400">
            <div>Host: {health?.hostname || 'N/A'}</div>
            <div>Uptime: {health?.uptime ? `${Math.floor(health.uptime / 60)}m` : 'N/A'}</div>
            <div>Memory: {health?.memory?.used || 'N/A'}</div>
            <div>Version: {health?.version || 'N/A'}</div>
          </div>
        </div>
      </main>
    </div>
  )
}

function StatCard({ title, value, color }) {
  const colors = {
    blue: 'bg-blue-900/30 border-blue-700 text-blue-300',
    green: 'bg-green-900/30 border-green-700 text-green-300',
    red: 'bg-red-900/30 border-red-700 text-red-300',
    purple: 'bg-purple-900/30 border-purple-700 text-purple-300',
  }
  return (
    <div className={`p-4 rounded-lg border ${colors[color]}`}>
      <div className="text-2xl font-bold">{value}</div>
      <div className="text-xs mt-1 opacity-80">{title}</div>
    </div>
  )
}

export default App
