const express = require('express');
const db = require('../db');
const os = require('os');

const router = express.Router();

// Health check - basic
router.get('/', async (req, res) => {
  const dbHealthy = await db.healthCheck();
  const status = dbHealthy ? 'healthy' : 'degraded';
  const httpStatus = dbHealthy ? 200 : 503;

  res.status(httpStatus).json({
    status,
    timestamp: new Date().toISOString(),
    service: 'cloud-platform-api',
    version: '1.0.0',
    uptime: process.uptime(),
    database: dbHealthy ? 'connected' : 'disconnected',
    hostname: os.hostname(),
    memory: {
      used: Math.round(process.memoryUsage().heapUsed / 1024 / 1024) + 'MB',
      total: Math.round(process.memoryUsage().heapTotal / 1024 / 1024) + 'MB'
    }
  });
});

// Liveness probe - is the process alive?
router.get('/live', (req, res) => {
  res.status(200).json({ status: 'alive' });
});

// Readiness probe - can it serve traffic?
router.get('/ready', async (req, res) => {
  const dbHealthy = await db.healthCheck();
  if (dbHealthy) {
    res.status(200).json({ status: 'ready' });
  } else {
    res.status(503).json({ status: 'not ready', reason: 'database unavailable' });
  }
});

module.exports = router;
