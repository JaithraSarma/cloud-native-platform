const { Pool } = require('pg');

const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: parseInt(process.env.DB_PORT || '5432', 10),
  database: process.env.DB_NAME || 'cloudplatform',
  user: process.env.DB_USER || 'appuser',
  password: process.env.DB_PASSWORD || 'apppassword',
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});

pool.on('error', (err) => {
  console.error('Unexpected database pool error:', err.message);
});

async function initialize() {
  const client = await pool.connect();
  try {
    await client.query(`
      CREATE TABLE IF NOT EXISTS products (
        id SERIAL PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        description TEXT,
        price DECIMAL(10, 2) NOT NULL CHECK (price >= 0),
        category VARCHAR(100),
        in_stock BOOLEAN DEFAULT true,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `);

    // Seed data if table is empty
    const { rows } = await client.query('SELECT COUNT(*) FROM products');
    if (parseInt(rows[0].count, 10) === 0) {
      await client.query(`
        INSERT INTO products (name, description, price, category, in_stock) VALUES
        ('Kubernetes Cluster License', 'Enterprise K8s cluster management license', 2999.99, 'Infrastructure', true),
        ('CI/CD Pipeline Setup', 'Automated pipeline configuration service', 499.99, 'DevOps', true),
        ('Container Registry', 'Private container image registry - 100GB', 149.99, 'Infrastructure', true),
        ('Helm Chart Bundle', 'Pre-configured Helm charts for common workloads', 79.99, 'DevOps', true),
        ('Monitoring Stack', 'Prometheus + Grafana monitoring suite', 299.99, 'Observability', true),
        ('SSL Certificate Pack', 'Wildcard SSL certificate - 1 year', 199.99, 'Security', true),
        ('Load Balancer Pro', 'Advanced L7 load balancing with WAF', 599.99, 'Networking', true),
        ('Disaster Recovery Plan', 'Multi-region DR setup and configuration', 1499.99, 'Infrastructure', false)
      `);
      console.log('Database seeded with initial products');
    }
  } finally {
    client.release();
  }
}

async function query(text, params) {
  const start = Date.now();
  const result = await pool.query(text, params);
  const duration = Date.now() - start;
  if (duration > 1000) {
    console.warn(`Slow query (${duration}ms):`, text);
  }
  return result;
}

async function healthCheck() {
  const client = await pool.connect();
  try {
    await client.query('SELECT 1');
    return true;
  } catch {
    return false;
  } finally {
    client.release();
  }
}

module.exports = { initialize, query, healthCheck, pool };
