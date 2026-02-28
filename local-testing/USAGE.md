# Quick Reference: Local Testing Scripts

All scripts can be run from anywhere (they auto-detect the repository root).

## Scripts Overview

### 1. `build-all-services.sh`
Builds all 4 services in dependency order with local proto dependencies.

**When to use:** After updating proto schemas, before starting the stack.

```bash
local-testing/build-all-services.sh
```

**What it does:**
- Cleans each service
- Regenerates proto classes (`generateProto`)
- Builds the service
- Publishes to Maven Local (`~/.m2/repository`)

**Build order:** IC → QRS → FPS → Conductor

---

### 2. `start-local-stack.sh`
Starts all 4 services configured to communicate via localhost.

**When to use:** After building, to run the full stack locally.

```bash
local-testing/start-local-stack.sh
```

**What it does:**
- Checks Redis is running
- Starts IC and QRS
- Waits 15 seconds
- Starts FPS (configured to call QRS on localhost:50060 and IC on localhost:50058)
- Waits 15 seconds
- Starts Conductor (configured to call localhost:50055)
- Saves PIDs to `/tmp/fps-stack-pids.txt`

**Logs:** `/tmp/ic.log`, `/tmp/qrs.log`, `/tmp/fps.log`, `/tmp/conductor.log`

---

### 3. `check-services.sh`
Checks health status of all services.

**When to use:** After starting services, to verify everything is ready.

```bash
local-testing/check-services.sh
```

**What it checks:**
- Redis connection (port 6380)
- Each service's healthcheck endpoint
- Port availability

**Exit codes:**
- `0` = All services healthy
- `1` = Some services not healthy

---

### 4. `stop-local-stack.sh`
Stops all running services gracefully.

**When to use:** When done testing, to clean up.

```bash
local-testing/stop-local-stack.sh
```

**What it does:**
- Reads PIDs from `/tmp/fps-stack-pids.txt`
- Kills each process
- Falls back to `pkill -f microservice-shell-java.jar` if no PID file
- Preserves logs in `/tmp/*.log`

---

## Typical Workflow

```bash
# 0. Prerequisites (required before starting the stack)
mshell login          # Refresh AWS credentials
sudo mshell proxy     # Start proxy (leave running in a separate terminal)

# 1. Update protos
cd quoteretrievalservice
protovend update
git commit -m "Update protos"

# 2. Build all services
cd ..
local-testing/build-all-services.sh

# 3. Start Redis (if not running)
redis-server --port 6380 &

# 4. Start stack
local-testing/start-local-stack.sh

# 5. Verify
local-testing/check-services.sh

# 6. Test (v1 JSON API)
curl "http://localhost:5020/v1/fps3/search" -s -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "X-Skyscanner-ChannelId: website" \
  -d '{"market":"UK","currency":"GBP","locale":"en-GB","adults":1,"cabin_class":"economy","legs":[{"origin":"EDI","destination":"LHR","date":"2026-03-15"}]}'

# 7. Debug
tail -f /tmp/conductor.log /tmp/fps.log /tmp/qrs.log /tmp/ic.log

# 8. Stop
cd ..
local-testing/stop-local-stack.sh
```

---

## Common Commands

### Watch all logs
```bash
tail -f /tmp/{conductor,fps,qrs,ic}.log
```

### Search logs for specific field
```bash
grep "your_field_name" /tmp/*.log
```

### Check Redis keys
```bash
redis-cli -p 6380 KEYS "*"
```

### Kill all services manually
```bash
pkill -f "microservice-shell-java.jar"
```

### Check ports in use
```bash
lsof -i :5020  # Conductor HTTP
lsof -i :5030  # FPS HTTP
lsof -i :5040  # IC HTTP
lsof -i :5050  # QRS HTTP
lsof -i :50058 # IC gRPC
lsof -i :50055 # FPS gRPC
lsof -i :50060 # QRS gRPC
lsof -i :50052 # Conductor gRPC
lsof -i :6380  # Redis
```

---

## Troubleshooting

### Scripts don't have permission
```bash
chmod +x local-testing/*.sh
```

### Services can't find each other
Check environment variables are set in start script and verify services are listening:
```bash
lsof -i :50058  # IC should be here
lsof -i :50055  # FPS should be here
lsof -i :50060  # QRS should be here
```

### Proto changes not reflected
```bash
# Clean and rebuild
local-testing/build-all-services.sh

# Verify mavenLocal() is FIRST in build.gradle repositories
```

### Redis errors
```bash
# Check Redis is running
redis-cli -p 6380 ping

# Start if not running
redis-server --port 6380 &
```

---

For comprehensive documentation, see [README.md](README.md)
