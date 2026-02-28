# Local Full-Stack Testing Guide

This guide explains how to run and test the flights-live-pricing-e2e-stack locally when you make changes that affect multiple services.

## Port Reference (Verified from dev.yml)

| Service | HTTP | Admin | gRPC |
|---------|------|-------|------|
| ItineraryConstruction (IC) | 5040 | 5041 | **50058** |
| QuoteRetrievalService (QRS) | 5050 | 5051 | 50060 |
| FlightsPricingSvc (FPS) | 5030 | 5031 | 50055 |
| Conductor | 5020 | 5021 | 50052 |
| Redis (FPS) | 6380 | - | - |
| Redis (Conductor) | 6380 (via env override) | - | - |

> **Note:** FPS defaults to Redis on port 6380 (`FPS_REDIS` env var). Conductor defaults to port **6379** (`CONDUCTOR_STORE_URL` env var) — we override it to 6380 so both services share one Redis instance.

## API Endpoints

Conductor exposes two API versions:

### v1 JSON API (Recommended for manual testing)

| Action | Method | URL | Content-Type |
|--------|--------|-----|--------------|
| Create | POST | `/v1/fps3/search` | `application/json` |
| Poll | GET | `/v1/fps3/search/{sessionKey}` | `application/json` |
| Booking Create | POST | `/v1/fps3/search/booking` | `application/json` |
| Booking Poll | GET | `/v1/fps3/search/{sessionKey}/booking/{itineraryId}` | `application/json` |

**Required header:** `X-Skyscanner-ChannelId: website`

### v2 Protobuf API

| Action | Method | URL | Content-Type |
|--------|--------|-----|--------------|
| Create | POST | `/api/v2/search/createSearch` | `application/x-protobuf-text-format` |
| Poll | POST | `/api/v2/search/pollSearch` | `application/x-protobuf-text-format` |

---

## Quick Start

### Prerequisites

1. Java installed (check each service's `build.gradle` for required version)
2. Redis installed: `brew install redis`
3. **AWS credentials** (required — services call real Skyscanner infrastructure):
   ```bash
   mshell login
   ```
4. **Proxy** (required — routes traffic to internal Skyscanner services):
   ```bash
   sudo mshell proxy
   ```
   Leave this running in a separate terminal for the duration of your local testing session.

### Step 1: Start Redis

```bash
redis-server --port 6380 --daemonize yes

# Verify
redis-cli -p 6380 ping  # Should return "PONG"
```

### Step 2: Start the Stack

**Option A: Use the script (recommended)**

```bash
local-testing/start-local-stack.sh
```

This starts all 4 services in the correct order with the right environment variables.

**Option B: Start manually**

Start services in dependency order (leaves first):

```bash
# Terminal 1 - ItineraryConstruction
cd itinerary-construction
java -jar build/libs/microservice-shell-java.jar server dev.yml

# Terminal 2 - QuoteRetrievalService
cd quoteretrievalservice
java -jar build/libs/microservice-shell-java.jar server dev.yml

# Wait for IC and QRS to be healthy, then:

# Terminal 3 - FlightsPricingSvc
cd flights-pricing-svc
FPS_QUOTE_RETRIEVAL_BASE_URL=localhost \
FPS_QUOTE_RETRIEVAL_PORT=50060 \
FPS_ITINERARY_CONSTRUCTION_BASE_URL_GRPC=localhost \
FPS_ITINERARY_CONSTRUCTION_PORT=50058 \
java -jar build/libs/microservice-shell-java.jar server dev.yml

# Wait for FPS to be healthy, then:

# Terminal 4 - Conductor
cd conductor
FPS_BASE_URL=localhost \
FPS_PORT=50055 \
CONDUCTOR_STORE_URL=127.0.0.1:6380 \
java -jar build/libs/microservice-shell-java.jar server dev.yml
```

### Step 3: Verify Services Are Running

```bash
local-testing/check-services.sh
```

Or manually:
```bash
curl http://localhost:5040/operations/healthcheck  # IC
curl http://localhost:5050/operations/healthcheck  # QRS
curl http://localhost:5030/operations/healthcheck  # FPS
curl http://localhost:5020/operations/healthcheck  # Conductor
```

All should return `{"healthy":true}` or similar.

### Step 4: Test End-to-End

**Option A: Use the automated test script**

```bash
local-testing/test-e2e.sh
```

**Option B: Test manually with curl**

```bash
# Create search session (EDI -> LHR)
curl "http://localhost:5020/v1/fps3/search" -s -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "X-Skyscanner-ChannelId: website" \
  -d '{"market":"UK","currency":"GBP","locale":"en-GB","adults":1,"cabin_class":"economy","legs":[{"origin":"EDI","destination":"LHR","date":"2026-03-15"}]}'
```

Extract `session_id` from the JSON response under `context.session_id`, then poll:

```bash
# Poll for results (replace {SESSION_ID} with actual value)
curl "http://localhost:5020/v1/fps3/search/{SESSION_ID}" -s -X GET \
  -H "Accept: application/json" \
  -H "X-Skyscanner-ChannelId: website"
```

Poll until all agents have `update_status: "current"`. Must be done within 60 seconds of create.

### Step 5: Stop Services

```bash
local-testing/stop-local-stack.sh
```

Or manually:
```bash
kill $(cat /tmp/fps-stack-pids.txt)
# or
pkill -f "microservice-shell-java.jar"
```

---

## Environment Variables Reference

### FPS (connecting to local IC and QRS)

| Variable | Value for Local Stack | Default (production) |
|----------|----------------------|---------------------|
| `FPS_QUOTE_RETRIEVAL_BASE_URL` | `localhost` | `quoteretrievalservice-cells.skyscanner.io` |
| `FPS_QUOTE_RETRIEVAL_PORT` | `50060` | `50051` |
| `FPS_ITINERARY_CONSTRUCTION_BASE_URL_GRPC` | `localhost` | `itineraryconstruction-cells.skyscanner.io` |
| `FPS_ITINERARY_CONSTRUCTION_PORT` | `50058` | `50051` |
| `FPS_REDIS` | `redis://127.0.0.1:6380` (default) | - |

### Conductor (connecting to local FPS)

| Variable | Value for Local Stack | Default (production) |
|----------|----------------------|---------------------|
| `FPS_BASE_URL` | `localhost` | `flights-pricing-svc-cells.skyscanner.io` |
| `FPS_PORT` | `50055` | `50051` |
| `CONDUCTOR_STORE_URL` | `127.0.0.1:6380` | `127.0.0.1:6379` |

> **Important:** The `FPS_ITINERARY_CONSTRUCTION_PORT` must be set to **50058** (IC's actual gRPC port), not 50051.
> The `CONDUCTOR_STORE_URL` must be set to port **6380** to match FPS's Redis instance.

---

## Building Services

### When to Build

Build is required:
- After cloning for the first time
- After updating proto schemas
- After code changes

### Full Build (all services, dependency order)

```bash
local-testing/build-all-services.sh
```

This builds IC -> QRS -> FPS -> Conductor, running `clean generateProto build publishToMavenLocal` for each.

### Individual Service Build

```bash
cd <service-directory>
./gradlew build
```

### Build with Local Proto Dependencies

If services depend on each other's proto definitions:

```bash
# Build in order, publishing to local Maven
cd itinerary-construction && ./gradlew clean generateProto build publishToMavenLocal
cd ../quoteretrievalservice && ./gradlew clean generateProto build publishToMavenLocal
cd ../flights-pricing-svc && ./gradlew clean generateProto build publishToMavenLocal
cd ../conductor && ./gradlew clean generateProto build publishToMavenLocal
```

Ensure `mavenLocal()` is first in your `build.gradle` repositories to pick up local artifacts:

```gradle
repositories {
    mavenLocal()
    maven { ... }
}
```

---

## Testing Strategies

### Strategy 1: Full Local Stack (Recommended for Cross-Service Changes)

Run all 4 services locally. See Quick Start above.

**Request flow:**
```
curl -> Conductor:5020 -> FPS:50055 -> QRS:50060 -> External Quote Service
                                    -> IC:50058
```

### Strategy 2: Single Service (Fastest Feedback Loop)

Run only the service you're changing. It will call production for dependencies.

```bash
cd flights-pricing-svc
./gradlew run
# FPS connects to production QRS and IC automatically
```

**Requirements:** AWS credentials + `mshell proxy`

### Strategy 3: Partial Stack

Run specific services locally, let others hit production.

```bash
# Example: FPS + IC locally, QRS via production
cd itinerary-construction && java -jar build/libs/microservice-shell-java.jar server dev.yml &

cd ../flights-pricing-svc
FPS_ITINERARY_CONSTRUCTION_BASE_URL_GRPC=localhost \
FPS_ITINERARY_CONSTRUCTION_PORT=50058 \
java -jar build/libs/microservice-shell-java.jar server dev.yml
```

---

## Troubleshooting

### Services can't connect to each other

1. **Verify ports are listening:**
   ```bash
   lsof -i :50058  # IC gRPC
   lsof -i :50060  # QRS gRPC
   lsof -i :50055  # FPS gRPC
   lsof -i :50052  # Conductor gRPC
   ```

2. **Check environment variables are set** in the terminal where you started the service.

3. **Check service logs:**
   ```bash
   tail -f /tmp/{ic,qrs,fps,conductor}.log
   ```

### FPS fails with Redis errors

```bash
# Verify Redis is running
redis-cli -p 6380 ping  # Should return "PONG"

# Start if not running
redis-server --port 6380 --daemonize yes

# Check keys (debugging)
redis-cli -p 6380 KEYS "*"
```

### Conductor Redis health check failures

Conductor defaults to Redis on port 6379. Set `CONDUCTOR_STORE_URL=127.0.0.1:6380` before starting Conductor.

### Services call production instead of localhost

Environment variables not set correctly. Verify:
```bash
echo $FPS_QUOTE_RETRIEVAL_BASE_URL      # should be "localhost"
echo $FPS_ITINERARY_CONSTRUCTION_PORT   # should be "50058"
echo $FPS_BASE_URL                      # should be "localhost"
echo $CONDUCTOR_STORE_URL               # should be "127.0.0.1:6380"
```

Restart the service after setting environment variables.

### External services (WhoToAsk, Quote Service) not accessible

These must be accessed via production/sandbox:
- Ensure VPN is connected
- Run `sudo mshell proxy`
- Check DNS: `nslookup whotoask-precompute.skyscanner.io`

### Port conflicts

```bash
# Find what's using a port
lsof -i :5020

# Kill the process
kill -9 <PID>
```

### Proto generation fails

```bash
cd <service>
./gradlew clean
rm -rf build/generated/source/proto/
./gradlew generateProto build
```

---

## Verification Checklist

Before considering your full-stack test complete:

- [ ] Redis running on port 6380 (`redis-cli -p 6380 ping`)
- [ ] All 4 services started and healthchecks pass
- [ ] Environment variables set for local service URLs (especially `FPS_ITINERARY_CONSTRUCTION_PORT=50058`)
- [ ] Conductor configured with `CONDUCTOR_STORE_URL=127.0.0.1:6380`
- [ ] gRPC ports listening: IC:50058, QRS:50060, FPS:50055, Conductor:50052
- [ ] Create request returns `session_id` in `context.session_id`
- [ ] Poll request returns itineraries and agents
- [ ] Requests flow through all services (check logs)
- [ ] No "Connection refused" or timeout errors in logs
- [ ] Redis contains session keys (`redis-cli -p 6380 KEYS "*"`)

---

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `build-all-services.sh` | Build all 4 services in dependency order |
| `start-local-stack.sh` | Start all services with correct env vars |
| `check-services.sh` | Health check all services + gRPC ports |
| `stop-local-stack.sh` | Stop all running services |
| `test-e2e.sh` | Automated create + poll E2E test |
| `test-grpc.sh` | gRPC testing with grpcurl |

---

## Tips

1. **Use `java -jar` directly** instead of `./gradlew run` for faster startup when builds exist
2. **Watch all logs:** `tail -f /tmp/{conductor,fps,qrs,ic}.log`
3. **Monitor Redis:** `redis-cli -p 6380 MONITOR`
4. **Clear state between tests:** `redis-cli -p 6380 FLUSHALL`
5. **Test both create and poll** — many bugs only appear during polling
6. **Use future dates** in search requests — past dates may not return results

---

## Additional Resources

- Individual service READMEs: `<service>/README.md`
- FPS sequence diagrams: `flights-pricing-svc/docs/pricing/*.puml`
- Example requests: `<service>/src/test/resources/examples/`
- External dependencies config: [EXTERNAL_DEPENDENCIES_CONFIG.md](EXTERNAL_DEPENDENCIES_CONFIG.md)
- Script usage guide: [USAGE.md](USAGE.md)