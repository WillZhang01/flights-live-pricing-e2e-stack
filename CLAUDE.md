# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is the **flights-live-pricing-e2e-stack** monorepo containing four microservices that work together to provide flight pricing functionality at Skyscanner. All services are built using MShell (Dropwizard + Guice), communicate via gRPC/protobuf, and are deployed to AWS via Slingshot.

### Service Architecture

The services form a request/response chain for flight pricing:

1. **conductor** - Search orchestration service that receives search requests and orchestrates backend services
   - Entry point for search requests
   - Coordinates with flights-pricing-svc
   - Local port: 5020 (HTTP), 5021 (admin), 50052 (gRPC)

2. **flights-pricing-svc** (FPS) - Central pricing service that orchestrates quote retrieval and itinerary construction
   - Main pricing logic and coordination
   - Calls quoteretrievalservice and itineraryconstruction
   - Local port: 5030 (HTTP), 5031 (admin), 50055 (gRPC)
   - Has comprehensive PlantUML sequence diagrams in `docs/pricing/` documenting the `create`, `poll`, `bookingCreateWithSessionRefresh`, and `bookingPoll` flows

3. **quoteretrievalservice** - Retrieves quotes from Quote Service (Live Update Service)
   - Handles quote retrieval from partners
   - Communicates with WhoToAsk service
   - Local port: 5050 (HTTP), 5051 (admin), 50060 (gRPC)

4. **itineraryconstruction** - Constructs flight itineraries from pricing data
   - Builds itineraries from quote data
   - Local port: 5040 (HTTP), 5041 (admin), 50058 (gRPC)

### End-to-End Flight Pricing Flow

The complete flow from a search request to pricing response involves all four services working together. Here's how they interact:

#### 1. Search Create Flow (Initial Request)

```
User/Frontend → Conductor → FPS → QRS → External Quote Service
                                  ↓
                                  IC → FPS → Conductor → User/Frontend
```

**Detailed steps:**

1. **Conductor receives search request** (v1 JSON: `POST /v1/fps3/search`, v2 proto: `POST /api/v2/search/createSearch`)
   - Validates the search query (origin, destination, dates, passengers)
   - Calls FPS via gRPC to initiate pricing

2. **FPS (flights-pricing-svc) orchestrates pricing** (`create` method)
   - Generates a unique `session_id` for tracking this search
   - **Cache check**: First attempts to serve from Itinerary Cache (Redis)
     - If cached data exists and is fresh → return immediately (fast path)
     - If cache miss or stale → continue to live pricing (slow path)
   - Prepares the search context (query params, experiments, channel ID)

3. **Quote Retrieval phase** (if not cached)
   - FPS calls **QuoteRetrievalService (QRS)** via gRPC `GetQuotes`
   - QRS queries **WhoToAsk** service to determine which travel partners to query
   - QRS fans out requests to **Quote Service** (Live Update Service) to fetch real-time prices from partners
   - QRS returns quote data back to FPS (includes agent info, pricing options, quote IDs)

4. **Itinerary Construction phase**
   - FPS calls **ItineraryConstruction** via gRPC with the quote data
   - IC combines quotes into complete flight itineraries
   - IC applies "skinny" logic to filter/rank/sort results
   - IC returns constructed itineraries to FPS

5. **State persistence and response**
   - FPS saves session state to **Redis** (FPS State Store) with the session_id
   - FPS writes itineraries to **Itinerary Cache** for future reuse
   - FPS tracks metrics and business events (session started, quote counts, latencies)
   - FPS returns response to Conductor with:
     - `session_id` for polling
     - Initial set of itineraries
     - Agent status (pending/completed)
   - Conductor forwards response to user

**Key concepts:**
- **Session ID**: Unique identifier (GUID) that ties together all requests in a search
- **Agent**: Represents a travel partner/supplier providing quotes
- **Cache-first strategy**: Always try to serve from cache before hitting live services
- **Asynchronous pricing**: Some agents may still be pending, requiring polling

#### 2. Poll Flow (Getting Live Updates)

```
User/Frontend → Conductor → FPS → QRS → External Quote Service
                                  ↓
                                  IC → FPS → Conductor → User/Frontend
```

**Detailed steps:**

1. **Conductor receives poll request** (v1 JSON: `GET /v1/fps3/search/{sessionKey}`, v2 proto: `POST /api/v2/search/pollSearch`)
   - Uses the `session_id` from create response
   - Calls FPS via gRPC to get updates

2. **FPS handles poll request** (`poll` method)
   - Retrieves session state from **Redis** using `session_id`
   - **Cache check**: If session was previously cached, serve from Itinerary Cache
   - If not cached, continue with live polling:

3. **Quote Updates phase** (for sessions with pending agents)
   - FPS calls **QRS** via gRPC `GetUpdates` with:
     - Session ID
     - List of quote requests that are still pending
     - Experiment overrides
   - QRS polls **Quote Service** for updated results from partners
   - QRS returns new/updated quote data

4. **Itinerary Update phase**
   - FPS merges new quotes into existing session state
   - Calls **ItineraryConstruction** if needed to rebuild itineraries
   - Applies "skinny" logic again for filtering/ranking
   - Checks if state has changed (etag comparison):
     - If unchanged → return 304 Not Modified
     - If changed → continue

5. **Response and persistence**
   - FPS updates session state in **Redis**
   - FPS saves updated itineraries to **Itinerary Cache**
   - FPS tracks completion metrics (when all agents finish)
   - Returns updated response with:
     - New/updated itineraries
     - Current agent status
     - Whether polling should continue
   - Conductor forwards to user

**Important timing:**
- Polls must occur within **60 seconds** of create request
- After 60s, pending live updates will timeout/fail
- Frontend typically polls every 1-2 seconds until all agents complete

#### 3. Booking Flow (Pre-redirect Verification)

When a user selects an itinerary to book, FPS performs a "booking create" to verify the price is still valid before redirecting to the partner:

```
User selects itinerary → Conductor → FPS → QRS → External Quote Service
                                           ↓
                                           IC → FPS → Conductor → Redirect to Partner
```

**Key differences from search flow:**
- Scoped to a specific `itinerary_id` and `session_id`
- Has a strict **10-minute staleness TTL** for quotes
- If quotes are stale, re-triggers live updates and requires polling
- Ensures user sees accurate price before leaving Skyscanner

#### External Service Dependencies

The services also interact with external Skyscanner services:

- **WhoToAsk** (via QRS): Determines which travel partners to query based on route, market, experiments
- **Quote Service / Live Update Service** (via QRS): External service that manages partner API calls
- **Redis (Elasticache)**:
  - FPS State Store: Stores mutable session state
  - Itinerary Cache: Stores complete pricing snapshots for fast retrieval
- **Fishmonger**: Configuration service for feature flags and experiments
- **Token Service**: Authentication tokens for external API calls
- **Grappler**: Logging, metrics, and business event tracking (sandbox/prod only)

#### State Management

- **Session State**: Stored in Redis, includes query params, quote data, itinerary results, agent status
- **Cache Strategy**: FPS uses Redis cache as write-through cache
  - Create: Check cache → miss → fetch live → store in cache
  - Poll: Check cache → if previously cached, serve from cache → else fetch updates
- **State Metadata**: Tracked separately to know if session was served from cache
- **ETags**: Used to detect state changes and avoid sending duplicate responses on poll

#### PlantUML Diagrams

For detailed sequence diagrams showing all internal component interactions within FPS, see:
- `flights-pricing-svc/docs/pricing/create-sequence.puml` - Full create flow with cache logic
- `flights-pricing-svc/docs/pricing/poll-sequence.puml` - Poll flow with state management
- `flights-pricing-svc/docs/pricing/booking-create-session-refresh-sequence.puml` - Booking verification
- `flights-pricing-svc/docs/pricing/booking-poll-sequence.puml` - Booking poll flow

### Technology Stack

- Java (versions vary: Java 8, 11, 17, 21)
- MShell framework (Dropwizard + Guice)
- gRPC/Protocol Buffers for inter-service communication
- Gradle for build system
- Docker for containerization
- AWS deployment via Slingshot
- buf for protobuf linting and breaking change detection

## Common Commands

All services follow similar patterns. Commands should be run from within the service directory (e.g., `cd conductor`).

### Building

```bash
./gradlew build
```

### Running Tests

```bash
./gradlew test
```

### Running Services Locally

#### As Java process (recommended for development):
```bash
./gradlew run
```

Or manually:
```bash
./gradlew build
java -jar build/libs/microservice-shell-java.jar server dev.yml
```

#### In Docker:
```bash
./gradlew build
docker-compose up
```

### Running Mutation Tests (Pitest)

```bash
./gradlew pitest
# View report:
open build/reports/pitest/index.html
```

### Protobuf Operations

#### Regenerate protobuf classes:
```bash
./gradlew generateProto
```

#### Verify protobuf changes (requires buf CLI):
```bash
# Lint
buf lint

# Check for breaking changes against master
buf breaking --against '.git#branch=master'
```

#### Update vendored protobuf schemas:
Use [`protovend`](https://confluence.skyscannertools.net/display/MS/Vendoring+Tool%3A+protovend) to manage vendored schemas from other services.

## Development Setup

### Prerequisites

- Java (version depends on service - check build.gradle)
- Gradle
- IntelliJ IDEA (recommended)
- Artifactory credentials (use `artifactory-cli-login gradle`)
- AWS credentials for integration tests
- Lombok plugin for IntelliJ
- Annotation processing enabled in IntelliJ

### Local Testing with AWS Resources

To test against production service dependencies and sandbox AWS resources:

1. Login to AWS:
   ```bash
   mshell-aws-login
   # Select: arn:aws:iam::295180981731:role/SandboxAccessADFS
   ```

2. Regenerate protos:
   ```bash
   ./gradlew generateProto
   ```

3. Configure IntelliJ to run with `server dev.yml` as program arguments

4. Start application in Debug mode

5. Test with curl using example protobuf requests in `src/test/resources/examples/`

### Testing FPS Locally

For flights-pricing-svc specifically (protobuf text format on port 5030):

#### Create request (initiates search session):
```bash
curl "http://localhost:5030/pricing/v1" -X POST \
  --data-binary @src/test/resources/examples/example_create.pb \
  -H "Content-Type: application/x-protobuf-text-format" \
  -H "Accept: application/x-protobuf-text-format"
```

#### Poll request (using session_id from create response):
```bash
curl "http://localhost:5030/pricing/v1/{session_id}" -X POST \
  --data-binary @src/test/resources/examples/example_poll.pb \
  -H "Content-Type: application/x-protobuf-text-format" \
  -H "Accept: application/x-protobuf-text-format"
```

Poll until all agents show status other than `pending`. Must be done within 60 seconds of create request.

#### Booking requests:
```bash
# Booking create
curl "http://localhost:5030/pricing/v1/{session_id}/{itinerary_id}/create" -X POST \
  --data-binary @src/test/resources/examples/example_booking.pb \
  -H "Content-Type: application/x-protobuf-text-format" \
  -H "Accept: application/x-protobuf-text-format"

# Booking poll
curl "http://localhost:5030/pricing/v1/{session_id}/{itinerary_id}/poll" -X POST \
  --data-binary @src/test/resources/examples/example_booking.pb \
  -H "Content-Type: application/x-protobuf-text-format" \
  -H "Accept: application/x-protobuf-text-format"
```

### Testing Conductor Locally

#### Create request (v1 JSON API on port 5020):
```bash
curl "http://localhost:5020/v1/fps3/search" -s -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "X-Skyscanner-ChannelId: website" \
  -d '{"market":"UK","currency":"GBP","locale":"en-GB","adults":1,"cabin_class":"economy","legs":[{"origin":"EDI","destination":"LHR","date":"2026-03-15"}]}'
```

#### Poll request:
Extract `session_id` from the create response JSON (`context.session_id`), then:
```bash
curl "http://localhost:5020/v1/fps3/search/{SESSION_ID}" -s -X GET \
  -H "Accept: application/json" \
  -H "X-Skyscanner-ChannelId: website"
```

## Project Structure

Each service follows a similar structure:

```
service-name/
├── build.gradle          # Build configuration
├── settings.gradle       # Gradle settings
├── dev.yml              # Development configuration
├── docker-compose.yml   # Docker setup
├── proto/               # Protobuf definitions
├── grpc/                # gRPC module (has own build.gradle)
├── src/
│   ├── main/java/net/skyscanner/  # Source code
│   └── test/                      # Tests
│       └── resources/examples/    # Example requests for local testing
├── cloudformation/      # AWS infrastructure definitions
└── .slingshot.yml       # Deployment configuration (if present)
```

## Configuration

Each service has three config files for different environments:
- `dev.yml` - Local development (console logging, points to sandbox/prod dependencies)
- `sandbox.yml` - Sandbox environment (Grappler logging with sandbox prefix)
- `prod.yml` - Production environment (Grappler logging with prod prefix)

The active config is selected via `CONFIGURATION_FILE_NAME` environment variable in `.slingshot.yml`.

## Local Full-Stack Testing

When making changes that affect multiple services, use the provided scripts in `local-testing/`:

### Quick Commands

```bash
# Build all services with local proto dependencies
local-testing/build-all-services.sh

# Start Redis
redis-server --port 6380 &

# Start the full stack (all 4 services)
local-testing/start-local-stack.sh

# Check all services are healthy
local-testing/check-services.sh

# Stop all services
local-testing/stop-local-stack.sh
```

For detailed guidance, see **[local-testing/README.md](local-testing/README.md)**:
- Testing proto schema changes across all services
- Running the full stack locally
- Hybrid local/remote testing strategies
- Docker-based testing
- Troubleshooting common issues
- Performance testing locally

## Important Notes

- **Certificate Trust**: You may need to add internal Skyscanner certificates to your JRE's trusted certificates for local development and integration tests
- **IntelliJ Code Insight**: For `ItineraryConstructionV1` class in FPS, you may need to increase IntelliJ's file size limit for code insight features if imports aren't working
- **Protobuf Breaking Changes**: Always run `buf breaking` before pushing protobuf changes to verify no breaking changes
- **Polling Timeouts**: Poll requests must be executed within 60 seconds of create requests, otherwise pending live updates will fail
- **Local Proxy**: You may need to run `mshell proxy` to access services in cells when testing locally

## Team & Communication

- **Team**: Dancing Penguins Squad
- **Slack**: #dancing-penguins
- **Email**: DancingPenguinsSquad@skyscanner.net
- **Documentation**: [Conductor Confluence space](https://confluence.skyscannertools.net/display/CONDUCTOR/) and [FPS Stage 2 Handover](https://confluence.skyscannertools.net/display/FPS/Stage+2+Handover)

## Related Skills

When working in this codebase, you have access to Skyscanner-specific skills:
- `service-golden-path:grpc-protobuf` - For gRPC/protobuf API work
- `service-golden-path:java-services` - For Java microservice development using MShell
- `service-golden-path:good-logging-and-errors` - For logging and error handling patterns
- `service-golden-path:production-standards` - For production readiness guidelines