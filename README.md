# Flights Live Pricing E2E Stack

Monorepo containing 4 microservices for flight pricing at Skyscanner:
- **conductor** - Search orchestration
- **flights-pricing-svc** (FPS) - Central pricing service
- **quoteretrievalservice** (QRS) - Quote retrieval from partners
- **itineraryconstruction** (IC) - Itinerary construction

## Quick Start

### For Local Development (Proto Schema Changes)

When you need to test proto schema changes across all services:

```bash
# 1. Update proto files in affected services
cd quoteretrievalservice
protovend update  # or manually update proto files
git add proto/ && git commit -m "Update protos"

# 2. Build all services with local proto dependencies
cd ..
local-testing/build-all-services.sh

# 3. Start Redis
redis-server --port 6380 &

# 4. Start the full stack
local-testing/start-local-stack.sh

# 5. Check services are healthy
local-testing/check-services.sh

# 6. Test end-to-end
cd conductor
curl "http://localhost:5020/api/v1/search/create" -s -X POST \
  --data-binary @src/test/resources/examples/proto_v1/create.pb \
  -H "Content-Type: application/x-protobuf-text-format" \
  -H "Accept: application/x-protobuf-text-format"

# 7. Stop services when done
cd ..
local-testing/stop-local-stack.sh
```

### For Single Service Development

```bash
cd <service-name>
./gradlew run
```

See individual service READMEs for details.

## Documentation

- **[CLAUDE.md](CLAUDE.md)** - Architecture overview, development guide for AI assistants
- **[local-testing/README.md](local-testing/README.md)** - Comprehensive local testing guide

## Local Testing Scripts

All scripts are in the `local-testing/` directory:

- **`build-all-services.sh`** - Build all services with local proto dependencies
- **`start-local-stack.sh`** - Start all 4 services locally
- **`stop-local-stack.sh`** - Stop all running services
- **`check-services.sh`** - Check health status of all services

## Service Ports

| Service | HTTP | Admin | gRPC |
|---------|------|-------|------|
| conductor | 5020 | 5021 | 50052 |
| flights-pricing-svc | 5030 | 5031 | 50055 |
| quoteretrievalservice | 5050 | 5051 | 50060 |
| itineraryconstruction | 5040 | 5041 | 50051 |

## Team

- **Slack**: #dancing-penguins
- **Email**: DancingPenguinsSquad@skyscanner.net