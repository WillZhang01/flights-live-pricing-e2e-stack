# Local E2E Stack Test Results

**Date:** 2026-02-15
**Test Duration:** ~2.5 hours
**Status:** ✅ Stack Running, ⚠️ Partial Functionality

## Stack Status

### Services Running ✅
All services successfully built and running:

| Service | Status | Port (HTTP) | Port (gRPC) | Health |
|---------|--------|-------------|-------------|--------|
| Redis | ✅ Running | 6380 | - | ✅ PONG |
| ItineraryConstruction | ✅ Running | 5040 | 50051 | ✅ 200 OK |
| QuoteRetrievalService | ✅ Running | 5050 | 50060 | ✅ 200 OK |
| FlightsPricingSvc | ✅ Running | 5030 | 50055 | ✅ 200 OK |
| Conductor | ✅ Running | 5020 | 50052 | ✅ 200 OK |

**Process IDs:** 78431 (IC), 87066 (QRS), 87533 (FPS), 87804 (Conductor)

### JAR Artifacts Built ✅
```
conductor/build/libs/microservice-shell-java.jar                    136M
flights-pricing-svc/build/libs/microservice-shell-java.jar          147M
itinerary-construction/build/libs/microservice-shell-java.jar       149M
quoteretrievalservice/build/libs/microservice-shell-java.jar        135M
```

## Test Request

### Request File
**Location:** `/tmp/test_fps_create.pb`

**Content:**
```protobuf
market: "UK"
currency: "GBP"
locale: "en-GB"
adults: 1
query_legs {
  origin: 11235
  destination: 13554
  date: "2026-03-15"
  return_date: "2026-03-17"
}
session_id_value: "88ea3c4f-e57f-4d8f-87a9-da89a7ee5a63"
query_options {
  include_unpriced_itineraries_value: true
  cached_prices_only_value: false
}
request {
  session_id: "88ea3c4f-e57f-4d8f-87a9-da89a7ee5a63"
  debug_options {
  }
  response_options {
    response_include: STATS
    response_include: DEEPLINK
    response_include: QUERY
    response_include: FQS
    response_include: PQS
  }
  query_context {
    device_is_mobile_value: false
    device_is_tablet_value: false
    channelId: WEBSITE
  }
}
```

### Test Command
```bash
curl "http://localhost:5030/pricing/v1" -s -X POST \
  --data-binary @/tmp/test_fps_create.pb \
  -H "Content-Type: application/x-protobuf-text-format" \
  -H "Accept: application/x-protobuf-text-format"
```

### Response
**Location:** `/tmp/test_fps_response.txt`

**Content:**
```protobuf
status {
  code: FAILED_PRECONDITION
  message: "Dependency Error: Itinerary Construction Service, buildItineraries. Got a INTERNAL error caused by UNKNOWN cause while calling Itinerary Construction: buildItineraries."
}
result_source: FLIGHTS_PRICING_SERVICE
```

## Issues Identified

### 1. Missing External Service Dependencies ⚠️
The services require external Skyscanner backend services that are not available locally:

**ItineraryConstruction Service Issues:**
- **Geo Service:** Unable to load geographical entity data
  ```
  net.skyscanner.geo.client.GeoDataClientException: Unable to read Geo entities
  JsonMappingException: Premature end of chunk coded message body
  ```
- **Agora Service:** Configuration service timeout
  ```
  io.grpc.StatusRuntimeException: DEADLINE_EXCEEDED: CallOptions deadline exceeded after 1.999s
  remote_addr=agora.skyscanner.io/127.0.0.1:50051
  ```

**FlightsPricingSvc Issues:**
- **Fishmonger (CasC):** Configuration service errors
  ```
  ERROR net.skyscanner.pelicans.fishmonger.client.CascCache:
  There was an error updating CasC Service PRODPARTNERS
  ```
- **Geo Health Check:** No geo data in memory
  ```
  ERROR net.skyscanner.fps.flightspricingsvc.healthcheck.GeoHealthCheck:
  Geo healthcheck failed, no data in memory
  ```

### 2. Services Successfully Communicate Locally ✅
- FPS successfully accepted protobuf request
- FPS successfully called ItineraryConstruction via gRPC
- Request flow worked: Client → FPS → IC
- Issue is IC's dependency on external services, not inter-service communication

## Setup Issues Encountered & Resolved

### 1. Java Version Compatibility ✅ FIXED
**Problem:** Services using Gradle 8.5 failed with Java 22
**Error:** `Unsupported class file major version 66`
**Solution:** Switched to Java 21 using asdf:
```bash
cd /Users/WillZhang/skyscanner-github/flights-live-pricing-e2e-stack
asdf local java temurin-21.0.2+13.0.LTS
```

### 2. Gradle Lock Conflicts ✅ FIXED
**Problem:** Multiple `./gradlew run` processes fighting over Gradle cache locks
**Error:** `Timeout waiting to lock file content cache`
**Solution:** Run services directly with JARs instead of Gradle:
```bash
java -jar build/libs/microservice-shell-java.jar server dev.yml
```

### 3. Artifactory Authentication ✅ FIXED
**Problem:** Gradle couldn't download dependencies
**Error:** `HTTP 401 Unauthorized` from artifactory.skyscannertools.net
**Solution:** Ran `artifactory-cli-login gradle` to authenticate

## Recommendations

### For Full E2E Testing
To test the complete stack end-to-end with actual flight pricing data, one of these approaches is needed:

1. **VPN + AWS Access:** Connect to Skyscanner VPN and use production/sandbox external services
   - Configure `mshell proxy` for service discovery
   - Services will call real Geo, Agora, WhoToAsk, Quote Service

2. **Mock External Dependencies:** Create stub services for Geo, Agora, etc.
   - Requires significant setup effort
   - Good for isolated testing

3. **Integration Test Environment:** Use Skyscanner's sandbox/staging environment
   - Services already deployed with all dependencies
   - Access via Slingshot deployment

### For Local Development
Current setup is sufficient for:
- ✅ Testing inter-service communication (gRPC, REST)
- ✅ Testing service startup and configuration
- ✅ Testing protobuf serialization/deserialization
- ✅ Debugging service-to-service interactions
- ✅ Testing Redis integration (FPS state storage)

## Stack Management Commands

### Start Stack
```bash
cd /Users/WillZhang/skyscanner-github/flights-live-pricing-e2e-stack
./local-testing/start-local-stack.sh
```

### Check Health
```bash
./local-testing/check-services.sh
```

### View Logs
```bash
tail -f /tmp/{ic,qrs,fps,conductor}.log
```

### Stop Stack
```bash
kill $(cat /tmp/fps-stack-pids.txt)
# or
pkill -f 'microservice-shell-java.jar'
```

### Clear Redis
```bash
redis-cli -p 6380 FLUSHALL
```

## Build Information

**Build Method:** `./gradlew clean build -x test --no-daemon`
**Java Version:** OpenJDK 21.0.2 (Temurin)
**Gradle Version:** 8.5 (FPS), 8.10.2 (IC, QRS, Conductor)
**Build Time:** ~7-10 minutes per service
**Test Execution:** Skipped (network issues with test dependencies)

## Conclusion

✅ **Success:** All 4 microservices built and running locally with Redis
✅ **Success:** Services communicate via gRPC/HTTP
✅ **Success:** Protobuf request/response working
⚠️  **Limitation:** External Skyscanner services (Geo, Agora, WhoToAsk, Quote Service) not accessible locally
⚠️  **Limitation:** Full flight pricing flow requires production/sandbox dependencies

**Next Steps:** For complete E2E testing, deploy to sandbox environment or configure VPN/proxy for external service access.
