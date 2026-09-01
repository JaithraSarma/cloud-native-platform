const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const pinoHttp = require('pino-http');
const rateLimit = require('express-rate-limit');
const { register, collectDefaultMetrics } = require('prom-client');
const productRoutes = require('./routes/products');
const healthRoutes = require('./routes/health');
const db = require('./db');
const logger = require('./logger');

const app = express();
const PORT = process.env.PORT || 3001;

// Load the OpenAPI spec once at startup so requests just serve the cached text
const openApiSpec = fs.readFileSync(path.join(__dirname, '..', 'openapi.yaml'), 'utf8');

// Collect default Prometheus metrics
collectDefaultMetrics();

// Security middleware
app.use(helmet());
app.use(cors({
  origin: process.env.CORS_ORIGIN || '*',
  methods: ['GET', 'POST', 'PUT', 'DELETE'],
  allowedHeaders: ['Content-Type', 'Authorization']
}));

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests, please try again later.' }
});
app.use('/api/', limiter);

// Request parsing & logging
app.use(express.json({ limit: '10kb' }));
app.use(pinoHttp({
  logger,
  genReqId: (req, res) => {
    const existingId = req.id ?? req.headers['x-request-id'];
    if (existingId) return existingId;
    const id = crypto.randomUUID();
    res.setHeader('X-Request-Id', id);
    return id;
  }
}));

// Routes
app.use('/api/products', productRoutes);
app.use('/health', healthRoutes);

// Prometheus metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// OpenAPI contract
app.get('/openapi.yaml', (req, res) => {
  res.set('Content-Type', 'application/yaml');
  res.send(openApiSpec);
});

// Root
app.get('/', (req, res) => {
  res.json({
    service: 'cloud-platform-api',
    version: '1.0.0',
    status: 'running',
    endpoints: {
      health: '/health',
      readiness: '/health/ready',
      liveness: '/health/live',
      metrics: '/metrics',
      products: '/api/products',
      openapi: '/openapi.yaml'
    }
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: 'Route not found' });
});

// Global error handler
app.use((err, req, res, next) => {
  logger.error({ err }, 'Unhandled error');
  res.status(500).json({ error: 'Internal server error' });
});

// Initialize database and start server
async function start() {
  try {
    await db.initialize();
    logger.info('Database initialized successfully');

    const server = app.listen(PORT, '0.0.0.0', () => {
      logger.info(`API server running on port ${PORT}`);
      logger.info(`Environment: ${process.env.NODE_ENV || 'development'}`);
    });

    let shuttingDown = false;
    const shutdown = (signal) => {
      if (shuttingDown) return;
      shuttingDown = true;

      logger.info(`${signal} received, shutting down gracefully`);

      const shutdownTimeoutMs = parseInt(process.env.SHUTDOWN_TIMEOUT_MS || '10000', 10);
      const forceExitTimer = setTimeout(() => {
        logger.error('Graceful shutdown timed out, forcing exit');
        process.exit(1);
      }, shutdownTimeoutMs);
      forceExitTimer.unref();

      server.close(async (err) => {
        if (err) {
          logger.error({ err }, 'Error while closing HTTP server');
        }
        try {
          await db.pool.end();
          logger.info('Database pool closed');
          clearTimeout(forceExitTimer);
          process.exit(0);
        } catch (closeErr) {
          logger.error({ err: closeErr }, 'Error while closing database pool');
          clearTimeout(forceExitTimer);
          process.exit(1);
        }
      });
    };

    process.on('SIGTERM', () => shutdown('SIGTERM'));
    process.on('SIGINT', () => shutdown('SIGINT'));
  } catch (err) {
    logger.error({ err }, 'Failed to start server');
    process.exit(1);
  }
}

if (process.env.NODE_ENV !== 'test') {
  start();
}

module.exports = app;
