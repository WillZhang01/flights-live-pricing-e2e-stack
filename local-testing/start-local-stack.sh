#!/bin/bash
# Start all 4 services locally for full-stack testing
# Logs are written to /tmp/*.log files
# Services communicate via localhost

set -e

PARENT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Export environment variables for local service communication
export FPS_QUOTE_RETRIEVAL_BASE_URL=localhost
export FPS_QUOTE_RETRIEVAL_PORT=50060
export FPS_ITINERARY_CONSTRUCTION_BASE_URL_GRPC=localhost
export FPS_ITINERARY_CONSTRUCTION_PORT=50058
export FPS_BASE_URL=localhost
export FPS_PORT=50055
export CONDUCTOR_STORE_URL=127.0.0.1:6380

echo "======================================"
echo "Starting Local Full Stack"
echo "======================================"
echo ""

# Check if Redis is running
if ! redis-cli -p 6380 ping > /dev/null 2>&1; then
    echo "⚠️  Redis is not running on port 6380"
    echo "   Start it with: redis-server --port 6380 &"
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    echo "✓ Redis is running on port 6380"
fi

echo ""
echo "Starting services in dependency order..."
echo ""

# Start ItineraryConstruction
echo "[1/4] Starting ItineraryConstruction..."
cd "$PARENT_DIR/itinerary-construction"
./gradlew run > /tmp/ic.log 2>&1 &
IC_PID=$!
echo "      Started (PID: $IC_PID) - Logs: /tmp/ic.log"

# Start QuoteRetrievalService
echo "[2/4] Starting QuoteRetrievalService..."
cd "$PARENT_DIR/quoteretrievalservice"
./gradlew run > /tmp/qrs.log 2>&1 &
QRS_PID=$!
echo "      Started (PID: $QRS_PID) - Logs: /tmp/qrs.log"

# Wait for IC and QRS to start
echo ""
echo "⏳ Waiting 15 seconds for IC and QRS to initialize..."
sleep 15

# Start FlightsPricingSvc
echo ""
echo "[3/4] Starting FlightsPricingSvc..."
cd "$PARENT_DIR/flights-pricing-svc"
FPS_QUOTE_RETRIEVAL_BASE_URL=$FPS_QUOTE_RETRIEVAL_BASE_URL \
FPS_QUOTE_RETRIEVAL_PORT=$FPS_QUOTE_RETRIEVAL_PORT \
FPS_ITINERARY_CONSTRUCTION_BASE_URL_GRPC=$FPS_ITINERARY_CONSTRUCTION_BASE_URL_GRPC \
FPS_ITINERARY_CONSTRUCTION_PORT=$FPS_ITINERARY_CONSTRUCTION_PORT \
./gradlew run > /tmp/fps.log 2>&1 &
FPS_PID=$!
echo "      Started (PID: $FPS_PID) - Logs: /tmp/fps.log"

# Wait for FPS to start
echo ""
echo "⏳ Waiting 15 seconds for FPS to initialize..."
sleep 15

# Start Conductor
echo ""
echo "[4/4] Starting Conductor..."
cd "$PARENT_DIR/conductor"
FPS_BASE_URL=$FPS_BASE_URL \
FPS_PORT=$FPS_PORT \
CONDUCTOR_STORE_URL=$CONDUCTOR_STORE_URL \
./gradlew run > /tmp/conductor.log 2>&1 &
CONDUCTOR_PID=$!
echo "      Started (PID: $CONDUCTOR_PID) - Logs: /tmp/conductor.log"

echo ""
echo "⏳ Waiting 10 seconds for Conductor to initialize..."
sleep 10

echo ""
echo "======================================"
echo "✓ All services started!"
echo "======================================"
echo ""
echo "Service Endpoints:"
echo "  IC:        http://localhost:5040 (gRPC: 50058)"
echo "  QRS:       http://localhost:5050 (gRPC: 50060)"
echo "  FPS:       http://localhost:5030 (gRPC: 50055)"
echo "  Conductor: http://localhost:5020 (gRPC: 50052)"
echo ""
echo "Healthchecks:"
echo "  curl http://localhost:5040/operations/healthcheck"
echo "  curl http://localhost:5050/operations/healthcheck"
echo "  curl http://localhost:5030/operations/healthcheck"
echo "  curl http://localhost:5020/operations/healthcheck"
echo ""
echo "Logs:"
echo "  tail -f /tmp/ic.log"
echo "  tail -f /tmp/qrs.log"
echo "  tail -f /tmp/fps.log"
echo "  tail -f /tmp/conductor.log"
echo ""
echo "  # Watch all logs:"
echo "  tail -f /tmp/{ic,qrs,fps,conductor}.log"
echo ""
echo "Process IDs:"
echo "  IC=$IC_PID QRS=$QRS_PID FPS=$FPS_PID CONDUCTOR=$CONDUCTOR_PID"
echo ""
echo "To stop all services:"
echo "  kill $IC_PID $QRS_PID $FPS_PID $CONDUCTOR_PID"
echo ""
echo "  # Or use:"
echo "  pkill -f 'microservice-shell-java.jar'"
echo ""
echo "Test the stack:"
echo "  cd conductor"
echo "  curl 'http://localhost:5020/api/v1/search/create' -s -X POST \\"
echo "    --data-binary @src/test/resources/examples/proto_v1/create.pb \\"
echo "    -H 'Content-Type: application/x-protobuf-text-format' \\"
echo "    -H 'Accept: application/x-protobuf-text-format'"
echo ""
echo "======================================"

# Save PIDs to a file for easy cleanup later
echo "$IC_PID $QRS_PID $FPS_PID $CONDUCTOR_PID" > /tmp/fps-stack-pids.txt
echo ""
echo "💾 PIDs saved to /tmp/fps-stack-pids.txt"
echo "   To stop later: kill \$(cat /tmp/fps-stack-pids.txt)"
echo ""