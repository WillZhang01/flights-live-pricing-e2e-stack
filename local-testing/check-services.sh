#!/bin/bash
# Check health status of all services

echo "======================================"
echo "Checking Service Health"
echo "======================================"
echo ""

check_service() {
    local name=$1
    local url=$2
    local port=$3

    printf "%-25s " "$name"

    # Check if port is listening
    if ! lsof -i :$port > /dev/null 2>&1; then
        echo "❌ Port $port not listening"
        return 1
    fi

    # Check healthcheck endpoint
    response=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null)

    if [ "$response" = "200" ]; then
        echo "✅ Healthy (HTTP $response)"
        return 0
    elif [ "$response" = "000" ]; then
        echo "⚠️  Port listening but no response"
        return 1
    else
        echo "⚠️  HTTP $response"
        return 1
    fi
}

# Check Redis
printf "%-25s " "Redis"
if redis-cli -p 6380 ping > /dev/null 2>&1; then
    echo "✅ Running"
    REDIS_OK=1
else
    echo "❌ Not running"
    REDIS_OK=0
fi

echo ""

# Check all services
check_service "ItineraryConstruction" "http://localhost:5040/operations/healthcheck" 5040
IC_OK=$?

check_service "QuoteRetrievalService" "http://localhost:5050/operations/healthcheck" 5050
QRS_OK=$?

check_service "FlightsPricingSvc" "http://localhost:5030/operations/healthcheck" 5030
FPS_OK=$?

check_service "Conductor" "http://localhost:5020/operations/healthcheck" 5020
CONDUCTOR_OK=$?

echo ""

# Check gRPC ports
echo "gRPC Ports:"
GRPC_OK=0
GRPC_TOTAL=0
for entry in "IC:50058" "QRS:50060" "FPS:50055" "Conductor:50052"; do
    name="${entry%%:*}"
    port="${entry##*:}"
    GRPC_TOTAL=$((GRPC_TOTAL+1))
    printf "%-25s " "  $name gRPC ($port)"
    if lsof -i :$port > /dev/null 2>&1; then
        echo "✅ Listening"
        GRPC_OK=$((GRPC_OK+1))
    else
        echo "❌ Not listening"
    fi
done
echo "  ($GRPC_OK/$GRPC_TOTAL gRPC ports listening)"

echo ""
echo "======================================"

# Summary
TOTAL=0
SUCCESS=0

if [ $REDIS_OK -eq 1 ]; then SUCCESS=$((SUCCESS+1)); fi; TOTAL=$((TOTAL+1))
if [ $IC_OK -eq 0 ]; then SUCCESS=$((SUCCESS+1)); fi; TOTAL=$((TOTAL+1))
if [ $QRS_OK -eq 0 ]; then SUCCESS=$((SUCCESS+1)); fi; TOTAL=$((TOTAL+1))
if [ $FPS_OK -eq 0 ]; then SUCCESS=$((SUCCESS+1)); fi; TOTAL=$((TOTAL+1))
if [ $CONDUCTOR_OK -eq 0 ]; then SUCCESS=$((SUCCESS+1)); fi; TOTAL=$((TOTAL+1))

echo "Status: $SUCCESS/$TOTAL services healthy"
echo "======================================"

if [ $SUCCESS -eq $TOTAL ]; then
    echo ""
    echo "✅ All services ready for testing!"
    echo ""
    echo "Test the stack:"
    echo "  curl 'http://localhost:5020/v1/fps3/search' -s -X POST \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -H 'Accept: application/json' \\"
    echo "    -H 'X-Skyscanner-ChannelId: website' \\"
    echo "    -d '{\"market\":\"UK\",\"currency\":\"GBP\",\"locale\":\"en-GB\",\"adults\":1,\"cabin_class\":\"economy\",\"legs\":[{\"origin\":\"EDI\",\"destination\":\"LHR\",\"date\":\"2026-03-15\"}]}'"
    echo ""
    exit 0
else
    echo ""
    echo "⚠️  Some services are not healthy"
    echo ""
    echo "Check logs:"
    echo "  tail -f /tmp/{ic,qrs,fps,conductor}.log"
    echo ""
    echo "Common issues:"
    echo "  • Redis not running: redis-server --port 6380 &"
    echo "  • Services not started: ./start-local-stack.sh"
    echo "  • Port conflicts: Check with 'lsof -i :<port>'"
    echo ""
    exit 1
fi