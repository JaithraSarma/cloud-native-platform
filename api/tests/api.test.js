const request = require('supertest');

// Mock the database module before requiring the app
jest.mock('../src/db', () => ({
  initialize: jest.fn().mockResolvedValue(),
  query: jest.fn(),
  healthCheck: jest.fn().mockResolvedValue(true),
  pool: { end: jest.fn() }
}));

const app = require('../src/server');
const db = require('../src/db');

describe('API Endpoints', () => {
  afterAll(async () => {
    await db.pool.end();
  });

  describe('GET /', () => {
    it('should return service info', async () => {
      const res = await request(app).get('/');
      expect(res.status).toBe(200);
      expect(res.body.service).toBe('cloud-platform-api');
      expect(res.body.status).toBe('running');
    });
  });

  describe('GET /health', () => {
    it('should return healthy status when db is connected', async () => {
      db.healthCheck.mockResolvedValue(true);
      const res = await request(app).get('/health');
      expect(res.status).toBe(200);
      expect(res.body.status).toBe('healthy');
    });

    it('should return degraded status when db is down', async () => {
      db.healthCheck.mockResolvedValue(false);
      const res = await request(app).get('/health');
      expect(res.status).toBe(503);
      expect(res.body.status).toBe('degraded');
    });
  });

  describe('GET /health/live', () => {
    it('should return alive', async () => {
      const res = await request(app).get('/health/live');
      expect(res.status).toBe(200);
      expect(res.body.status).toBe('alive');
    });
  });

  describe('GET /health/ready', () => {
    it('should return ready when db is healthy', async () => {
      db.healthCheck.mockResolvedValue(true);
      const res = await request(app).get('/health/ready');
      expect(res.status).toBe(200);
      expect(res.body.status).toBe('ready');
    });
  });

  describe('GET /api/products', () => {
    it('should return products list', async () => {
      const mockProducts = [
        { id: 1, name: 'Test Product', price: 9.99, category: 'Test' }
      ];
      db.query.mockResolvedValue({ rows: mockProducts });

      const res = await request(app).get('/api/products');
      expect(res.status).toBe(200);
      expect(res.body.products).toEqual(mockProducts);
      expect(res.body.count).toBe(1);
    });
  });

  describe('GET /api/products/:id', () => {
    it('should return a product by id', async () => {
      const mockProduct = { id: 1, name: 'Test', price: 9.99 };
      db.query.mockResolvedValue({ rows: [mockProduct] });

      const res = await request(app).get('/api/products/1');
      expect(res.status).toBe(200);
      expect(res.body).toEqual(mockProduct);
    });

    it('should return 404 for non-existent product', async () => {
      db.query.mockResolvedValue({ rows: [] });

      const res = await request(app).get('/api/products/999');
      expect(res.status).toBe(404);
    });

    it('should return 400 for invalid id', async () => {
      const res = await request(app).get('/api/products/abc');
      expect(res.status).toBe(400);
    });
  });

  describe('POST /api/products', () => {
    it('should create a new product', async () => {
      const newProduct = { name: 'New Product', price: 19.99, category: 'Test' };
      const created = { id: 2, ...newProduct, in_stock: true };
      db.query.mockResolvedValue({ rows: [created] });

      const res = await request(app)
        .post('/api/products')
        .send(newProduct);
      expect(res.status).toBe(201);
      expect(res.body.name).toBe('New Product');
    });

    it('should return 400 for missing name', async () => {
      const res = await request(app)
        .post('/api/products')
        .send({ price: 19.99 });
      expect(res.status).toBe(400);
    });
  });

  describe('404 handler', () => {
    it('should return 404 for unknown routes', async () => {
      const res = await request(app).get('/unknown');
      expect(res.status).toBe(404);
    });
  });
});
