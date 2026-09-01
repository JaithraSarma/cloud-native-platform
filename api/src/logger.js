const pino = require('pino');

const level = process.env.NODE_ENV === 'test'
  ? 'silent'
  : (process.env.LOG_LEVEL || 'info');

const logger = pino({ level });

module.exports = logger;
