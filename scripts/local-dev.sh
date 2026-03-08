#!/bin/bash
set -euo pipefail

# ============================================================================
# Local Development with Docker Compose
# ============================================================================

echo "=== Starting local development environment ==="

docker compose up --build -d

echo "Waiting for services to be healthy..."
sleep 15

echo ""
echo "=== Services Running ==="
echo "  Frontend:  http://localhost:8080"
echo "  API:       http://localhost:3001"
echo "  Health:    http://localhost:3001/health"
echo "  Products:  http://localhost:3001/api/products"
echo "  Metrics:   http://localhost:3001/metrics"
echo ""

# Quick health check
curl -s http://localhost:3001/health | python3 -m json.tool 2>/dev/null || echo "API starting up..."
echo ""
echo "Run 'docker compose logs -f' to watch logs"
echo "Run 'docker compose down -v' to stop and clean up"
