# External Service Dependencies Configuration Review

**Date:** 2026-02-15
**Status:** ✅ All external services correctly configured to use production URLs

## Summary

All services in the local stack are correctly configured to call **real Skyscanner production services** for external dependencies. The issue preventing full E2E testing is **network connectivity**, not configuration.

---

## Configuration Analysis by Service

### 1. ItineraryConstruction (IC)

**Config File:** `itinerary-construction/dev.yml`

#### External Dependencies - All Correctly Configured ✅

| Service | Type | Configuration | Status |
|---------|------|---------------|--------|
| **Agora** | gRPC | `agora.skyscanner.io:50051` | ✅ Correct |
| **Geo Data Service** | HTTP | `http://flights-geo.skyscanner.io` | ✅ Correct |
| **Fishmonger** (Config) | HTTP | `http://fishmonger.skyscanner.io` | ✅ Correct |
| **Token Service** | HTTP | Foreign service discovery | ✅ Correct |
| **Travel API** | HTTP | `http://terra-proxy.skyscanner.io` | ✅ Correct |
| **Culture Service** | HTTP | `http://culture-data-service-cells.skyscanner.io` | ✅ Correct |
| **Relevance Service** | gRPC | `relevance-service.skyscanner.io:50051` | ✅ Correct |
| **Fare Attributes** | gRPC | `fare-attributes-svc.skyscanner.io:50051` | ✅ Correct |
| **Partner Metadata** | gRPC | `partner-metadata-svc.skyscanner.io:50051` | ✅ Correct |
| **Unpriced Itineraries** | HTTP | `http://unpriced-itineraries-cells.skyscanner.io` | ✅ Correct |
| **Carriers Data** | HTTP | `carriers.skyscanner.io` | ✅ Correct |
| **Sansiro (Partner Activation)** | HTTP | `http://sansiro-cells.skyscanner.io/` | ✅ Correct |

**Key Configuration Sections:**
```yaml
# Lines 139-148: Agora (gRPC)
agora:
  foreignServiceName: agora
  host: agora.skyscanner.io
  port: 50051

# Lines 209-210: Geo Data
reference_data:
  geo:
    url: http://flights-geo.skyscanner.io

# Line 94-95: Fishmonger
fishmonger:
  baseUrl: http://fishmonger.skyscanner.io
```

---

### 2. FlightsPricingSvc (FPS)

**Config File:** `flights-pricing-svc/dev.yml`

#### External Dependencies - All Correctly Configured ✅

| Service | Type | Configuration | Status |
|---------|------|---------------|--------|
| **QuoteRetrievalService** | gRPC | `localhost:50060` (env override) | ✅ Correct (local) |
| **ItineraryConstruction** | gRPC | `localhost:50058` (env override) | ✅ Correct (local) |
| **Fishmonger** (Config) | HTTP | `http://fishmonger.skyscanner.io` | ✅ Correct |
| **Geo Service** | HTTP | `http://flights-geo.skyscanner.io` | ✅ Correct |
| **Token Service** | HTTP | Foreign service discovery | ✅ Correct |
| **Travel API** | HTTP | `http://terra-proxy.skyscanner.io` | ✅ Correct |
| **Relevance Service** | gRPC | `relevance-service.skyscanner.io:50051` | ✅ Correct |
| **Global Cache Proxy** | HTTP | `http://global-cache-proxy.skyscanner.io` | ✅ Correct |
| **Carriers Data** | HTTP | `carriers.skyscanner.io` | ✅ Correct |
| **Redis** | Redis | `redis://127.0.0.1:6380` | ✅ Correct (local) |

**Key Configuration Sections:**
```yaml
# Lines 132-143: IC and QRS (correctly overridden to localhost)
quoteretrievalservice:
  foreignServiceName: quoteretrievalservice-cells
  host: ${FPS_QUOTE_RETRIEVAL_BASE_URL:-quoteretrievalservice-cells.skyscanner.io}
  port: ${FPS_QUOTE_RETRIEVAL_PORT:-50051}

itineraryconstruction:
  foreignServiceName: itineraryconstruction-cells
  host: ${FPS_ITINERARY_CONSTRUCTION_BASE_URL_GRPC:-itineraryconstruction-cells.skyscanner.io}
  port: ${FPS_ITINERARY_CONSTRUCTION_PORT:-50051}

# Lines 93-100: Geo Service
net.skyscanner.flightspricing.geoservice:
  baseUrl: http://flights-geo.skyscanner.io

# Lines 85-92: Fishmonger
fishmonger:
  baseUrl: http://fishmonger.skyscanner.io
```

**Environment Variables Set:**
```bash
FPS_QUOTE_RETRIEVAL_BASE_URL=localhost
FPS_QUOTE_RETRIEVAL_PORT=50060
FPS_ITINERARY_CONSTRUCTION_BASE_URL_GRPC=localhost
FPS_ITINERARY_CONSTRUCTION_PORT=50058
```

---

### 3. QuoteRetrievalService (QRS)

**Config File:** `quoteretrievalservice/dev.yml`

#### External Dependencies - All Correctly Configured ✅

| Service | Type | Configuration | Status |
|---------|------|---------------|--------|
| **WhoToAsk** | HTTP | `http://whotoask-precompute.skyscanner.io` | ✅ Correct |
| **Quote Service** | gRPC | `quoteservice-cells.skyscanner.io:50051` | ✅ Correct |
| **Geo Data Service** | HTTP | `http://flights-geo.skyscanner.io` | ✅ Correct |
| **Fishmonger** (Config) | HTTP | `http://fishmonger.skyscanner.io` | ✅ Correct |
| **Carriers Data** | HTTP | `carriers.skyscanner.io` | ✅ Correct |

**Key Configuration Sections:**
```yaml
# Lines 77-86: WhoToAsk
net.skyscanner.dps.whotoask:
  foreignServiceName: whotoask-precompute
  baseUrl: http://whotoask-precompute.skyscanner.io

# Lines 100-106: Quote Service (gRPC)
quoteservice.quoteservice.v1.QuoteServiceV1:
  foreignServiceName: quoteservice-cells
  host: quoteservice-cells.skyscanner.io
  port: 50051

# Lines 151-152: Geo Data
geo_data:
  base_url: http://flights-geo.skyscanner.io
```

---

### 4. Conductor

**Config File:** `conductor/dev.yml`

#### External Dependencies - All Correctly Configured ✅

| Service | Type | Configuration | Status |
|---------|------|---------------|--------|
| **FlightsPricingSvc** | gRPC | `localhost:50055` (env override) | ✅ Correct (local) |
| **Fishmonger** (Config) | HTTP | `http://fishmonger.skyscanner.io` | ✅ Correct |
| **Geo Data Service** | HTTP | `http://flights-geo.skyscanner.io` | ✅ Correct |
| **Token Service** | HTTP | Foreign service discovery | ✅ Correct |
| **Carriers Data** | HTTP | `carriers.skyscanner.io` | ✅ Correct |

**Key Configuration Sections:**
```yaml
# Lines 101-106: FPS (correctly overridden to localhost)
flights-pricing-svc:
  foreignServiceName: flights-pricing-svc
  host: ${FPS_BASE_URL:-flights-pricing-svc-cells.skyscanner.io}
  port: ${FPS_PORT:-50051}

# Lines 163-164: Geo Data
externalServices:
  geo_data:
    service_url: "http://flights-geo.skyscanner.io"

# Lines 89-94: Fishmonger
fishmonger:
  baseUrl: http://fishmonger.skyscanner.io
```

**Environment Variables Set:**
```bash
FPS_BASE_URL=localhost
FPS_PORT=50055
```

---

## Network Connectivity Issues

### The Real Problem: Services Cannot Reach External URLs

The configuration is **100% correct**, but services cannot reach external Skyscanner infrastructure because:

#### 1. **Network Isolation**
Local machine is not on Skyscanner's internal network/VPN where these services are accessible.

#### 2. **DNS Resolution**
These domains (`.skyscanner.io`) may be:
- Internal-only DNS (not publicly routable)
- Behind Skyscanner's firewall
- Require VPN or proxy access

#### 3. **Service Discovery**
Some services use "foreign service" discovery which requires:
- Skyscanner's service mesh
- K8s service discovery
- AWS service discovery (Cloud Map)

---

## Solutions to Enable Full E2E Testing

### Option 1: VPN + Proxy (Recommended for Local Dev)

**Requirements:**
- Connect to Skyscanner VPN
- Run `mshell proxy` for service discovery
- Configure AWS credentials for sandbox account

**Setup:**
```bash
# 1. Connect to Skyscanner VPN
# (Use your company's VPN client)

# 2. Refresh credentials
mshell login

# 3. Start mshell proxy for service discovery
sudo mshell proxy

# 4. Restart services
./local-testing/start-local-stack.sh
```

**Expected Result:**
- ✅ Services can resolve `.skyscanner.io` domains
- ✅ Can reach Geo, Agora, WhoToAsk, Quote Service
- ✅ Full E2E flight pricing flow works

---

### Option 2: Use Sandbox/Production Environment

**Instead of running locally, deploy to Skyscanner's environments:**

```bash
# Deploy to sandbox
cd <service-directory>
slc deploy sandbox

# Test via sandbox URLs
curl "https://flights-pricing-svc-sandbox.skyscanner.io/..."
```

**Benefits:**
- All external dependencies available
- Real infrastructure (Redis, AWS services)
- No local setup needed

---

### Option 3: Mock External Services (Complex)

Create mock/stub services for:
- Geo Data Service (return fake airport/geo data)
- Agora (return fake configuration)
- WhoToAsk (return fake partner list)
- Quote Service (return fake quotes)

**Pros:** Fully isolated local testing
**Cons:** Significant setup effort, doesn't test real integrations

---

## Current Setup Status

### What Works ✅
1. **Inter-service communication:**
   - Conductor → FPS ✅
   - FPS → IC ✅
   - FPS → QRS ✅

2. **Local dependencies:**
   - Redis (port 6380) ✅
   - All services running and healthy ✅
   - Protobuf serialization ✅

3. **Configuration:**
   - All external service URLs correct ✅
   - Environment variable overrides working ✅

### What Doesn't Work ⚠️
1. **External service calls fail with:**
   - Connection timeouts
   - DNS resolution failures
   - DEADLINE_EXCEEDED errors

2. **Affected features:**
   - Geo data loading (airports, cities)
   - Configuration loading (Fishmonger, Agora)
   - Partner selection (WhoToAsk)
   - Quote retrieval (Quote Service)
   - **Result:** Cannot complete flight pricing requests

---

## Testing Without External Services

### What You Can Test Locally

Even without external service connectivity, you can test:

#### 1. Service Communication
```bash
# Test FPS accepts requests
curl "http://localhost:5030/pricing/v1" -X POST \
  --data-binary @test_request.pb \
  -H "Content-Type: application/x-protobuf-text-format"
```

#### 2. gRPC Communication
- FPS → IC (confirmed working)
- FPS → QRS (confirmed working)
- Conductor → FPS (confirmed working)

#### 3. Redis Integration
```bash
# Check FPS writes to Redis
redis-cli -p 6380 KEYS "*"
```

#### 4. Configuration Loading
- Services load their dev.yml configs ✅
- Environment variable overrides work ✅

#### 5. Protobuf Parsing
- Request/response serialization ✅
- Schema validation ✅

---

## Verification Commands

### Check External Service Connectivity

```bash
# Test if you can reach external services
curl -I http://fishmonger.skyscanner.io
curl -I http://flights-geo.skyscanner.io
curl -I http://whotoask-precompute.skyscanner.io

# Check DNS resolution
nslookup agora.skyscanner.io
nslookup quoteservice-cells.skyscanner.io

# Check if mshell proxy is running
ps aux | grep "mshell proxy"
```

### Monitor Service Logs for External Calls

```bash
# Watch for external service call attempts
tail -f /tmp/{ic,qrs,fps,conductor}.log | grep -E "skyscanner.io|DEADLINE|Connection|timeout"
```

---

## Recommendations

### For Current Local Development:
1. **Focus on inter-service testing** - this works perfectly
2. **Use unit/integration tests** - mock external services
3. **Test individual service logic** - without full E2E flow

### For Full E2E Testing:
1. **Use VPN + mshell proxy** - enables local access to all services
2. **Deploy to sandbox** - recommended for integration testing
3. **Use production** - for final validation before release

### For CI/CD:
- Integration tests should run in sandbox environment
- Local stack useful for development, not CI
- Use test fixtures/mocks for external dependencies

---

## Summary Table

| Service | Configuration | Connectivity | Recommendation |
|---------|---------------|--------------|----------------|
| Agora | ✅ Correct | ❌ Cannot reach | Use VPN |
| Geo Service | ✅ Correct | ❌ Cannot reach | Use VPN |
| Fishmonger | ✅ Correct | ❌ Cannot reach | Use VPN |
| WhoToAsk | ✅ Correct | ❌ Cannot reach | Use VPN |
| Quote Service | ✅ Correct | ❌ Cannot reach | Use VPN |
| IC (local) | ✅ Correct | ✅ Working | Keep as-is |
| QRS (local) | ✅ Correct | ✅ Working | Keep as-is |
| FPS (local) | ✅ Correct | ✅ Working | Keep as-is |
| Conductor (local) | ✅ Correct | ✅ Working | Keep as-is |
| Redis (local) | ✅ Correct | ✅ Working | Keep as-is |

---

## Conclusion

✅ **Configuration is perfect** - all services correctly point to real Skyscanner infrastructure
❌ **Network connectivity is the blocker** - cannot reach internal services from local machine
🔧 **Solution:** Connect to VPN and use `mshell proxy` for full E2E testing

The local stack is working exactly as designed - it's ready for full testing once network access to Skyscanner's internal services is established.
