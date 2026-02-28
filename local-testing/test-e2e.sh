#!/bin/bash
# End-to-end test script for flights-live-pricing stack
# Uses the v1 JSON API (POST /v1/fps3/search for create, GET /v1/fps3/search/{sessionKey} for poll)
set -e

CONDUCTOR_URL="${CONDUCTOR_URL:-http://localhost:5020}"

# Default search: EDI->LHR, 30 days from now
DEFAULT_DATE=$(date -v+30d +%Y-%m-%d 2>/dev/null || date -d "+30 days" +%Y-%m-%d 2>/dev/null || echo "2026-04-15")
SEARCH_ORIGIN="${SEARCH_ORIGIN:-EDI}"
SEARCH_DESTINATION="${SEARCH_DESTINATION:-LHR}"
SEARCH_DATE="${SEARCH_DATE:-$DEFAULT_DATE}"

echo "============================================"
echo "E2E Test: Flights Live Pricing Stack"
echo "============================================"
echo ""
echo "Search: ${SEARCH_ORIGIN} -> ${SEARCH_DESTINATION} on ${SEARCH_DATE}"
echo ""

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Step 1: Health checks
echo -e "${BLUE}[1/4] Checking service health...${NC}"
for service in "conductor:5020" "fps:5030" "qrs:5050" "ic:5040"; do
    name="${service%%:*}"
    port="${service##*:}"
    if curl -sf "http://localhost:${port}/operations/healthcheck" > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} ${name} is healthy"
    else
        echo -e "  ${RED}✗${NC} ${name} is not responding on port ${port}"
        exit 1
    fi
done
echo ""

# Step 2: Create search session (v1 JSON API)
echo -e "${BLUE}[2/4] Creating search session...${NC}"
CREATE_RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -H "X-Skyscanner-ChannelId: website" \
    -d "{\"market\":\"UK\",\"currency\":\"GBP\",\"locale\":\"en-GB\",\"adults\":1,\"cabin_class\":\"economy\",\"legs\":[{\"origin\":\"${SEARCH_ORIGIN}\",\"destination\":\"${SEARCH_DESTINATION}\",\"date\":\"${SEARCH_DATE}\"}]}" \
    "${CONDUCTOR_URL}/v1/fps3/search")

echo "$CREATE_RESPONSE" > /tmp/e2e_create_response.json

# Extract session_id from JSON response
SESSION_ID=$(echo "$CREATE_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['context']['session_id'])" 2>/dev/null)

if [ -z "$SESSION_ID" ]; then
    echo -e "${RED}✗ Failed to extract session_id from response${NC}"
    echo "Response (first 500 chars):"
    echo "$CREATE_RESPONSE" | head -c 500
    exit 1
fi

echo -e "  ${GREEN}✓${NC} Session created: ${SESSION_ID}"

# Extract counts from JSON
ITINERARY_COUNT=$(echo "$CREATE_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('itineraries',[])))" 2>/dev/null || echo "0")
AGENT_COUNT=$(echo "$CREATE_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('agents',[])))" 2>/dev/null || echo "0")
echo "  -> Agents: ${AGENT_COUNT}, Itineraries: ${ITINERARY_COUNT}"
echo ""

# Step 3: Poll for updates (v1 JSON API - GET with session key)
echo -e "${BLUE}[3/4] Polling for live updates...${NC}"

MAX_POLLS=5
POLL_INTERVAL=2
POLL_ITINERARY_COUNT=0
ALL_COMPLETE="false"

for i in $(seq 1 $MAX_POLLS); do
    echo "  Poll attempt ${i}/${MAX_POLLS}..."

    POLL_RESPONSE=$(curl -s -X GET \
        -H "Accept: application/json" \
        -H "X-Skyscanner-ChannelId: website" \
        "${CONDUCTOR_URL}/v1/fps3/search/${SESSION_ID}")

    echo "$POLL_RESPONSE" > "/tmp/e2e_poll_response_${i}.json"

    # Parse JSON response
    POLL_RESULT=$(echo "$POLL_RESPONSE" | python3 -c "
import sys, json
d = json.load(sys.stdin)
itins = len(d.get('itineraries', []))
agents = d.get('agents', [])
total = len(agents)
current = sum(1 for a in agents if isinstance(a, dict) and a.get('update_status') == 'current')
pending = total - current
print(f'{itins} {total} {current} {pending}')
" 2>/dev/null || echo "0 0 0 0")

    POLL_ITINERARY_COUNT=$(echo "$POLL_RESULT" | awk '{print $1}')
    TOTAL_AGENTS=$(echo "$POLL_RESULT" | awk '{print $2}')
    CURRENT_AGENTS=$(echo "$POLL_RESULT" | awk '{print $3}')
    PENDING_AGENTS=$(echo "$POLL_RESULT" | awk '{print $4}')

    echo "    -> Itineraries: ${POLL_ITINERARY_COUNT}, Agents: ${CURRENT_AGENTS}/${TOTAL_AGENTS} complete"

    if [ "$PENDING_AGENTS" = "0" ] && [ "$CURRENT_AGENTS" != "0" ]; then
        echo -e "  ${GREEN}✓${NC} All agents completed!"
        ALL_COMPLETE="true"
        break
    fi

    if [ $i -lt $MAX_POLLS ]; then
        sleep $POLL_INTERVAL
    fi
done

if [ "$ALL_COMPLETE" != "true" ]; then
    echo -e "  ${RED}⚠${NC} Some agents still pending after ${MAX_POLLS} polls (may be normal for slow partners)"
fi
echo ""

# Step 4: Validate results
echo -e "${BLUE}[4/4] Validating results...${NC}"

VALIDATION_FAILED=0

# Check session_id is valid UUID format
if [[ ! "$SESSION_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    echo -e "  ${RED}✗${NC} session_id is not a valid UUID: ${SESSION_ID}"
    VALIDATION_FAILED=1
else
    echo -e "  ${GREEN}✓${NC} session_id format is valid"
fi

# Check we have itineraries
if [ "$POLL_ITINERARY_COUNT" -gt 0 ] 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Received itineraries: ${POLL_ITINERARY_COUNT}"
else
    echo -e "  ${RED}✗${NC} No itineraries returned"
    VALIDATION_FAILED=1
fi

# Check response contains required JSON fields
LAST_POLL="/tmp/e2e_poll_response_${i}.json"
REQUIRED_FIELDS=("itineraries" "agents" "legs" "segments" "context")
for field in "${REQUIRED_FIELDS[@]}"; do
    if grep -q "\"$field\"" "$LAST_POLL"; then
        echo -e "  ${GREEN}✓${NC} Response contains '${field}'"
    else
        echo -e "  ${RED}✗${NC} Response missing '${field}'"
        VALIDATION_FAILED=1
    fi
done

# Check Redis has session state
if redis-cli -p 6380 EXISTS "$SESSION_ID" 2>/dev/null | grep -q "1"; then
    echo -e "  ${GREEN}✓${NC} Session state stored in Redis"
else
    echo -e "  ${RED}⚠${NC} Session not found in Redis (may have expired or be on different key format)"
fi

echo ""
echo "============================================"
if [ $VALIDATION_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ E2E TEST PASSED${NC}"
    echo "============================================"
    echo ""
    echo "Response files saved:"
    echo "  - /tmp/e2e_create_response.json"
    echo "  - /tmp/e2e_poll_response_*.json"
    exit 0
else
    echo -e "${RED}✗ E2E TEST FAILED${NC}"
    echo "============================================"
    echo ""
    echo "Check response files for details:"
    echo "  - /tmp/e2e_create_response.json"
    echo "  - /tmp/e2e_poll_response_*.json"
    echo ""
    echo "Check service logs:"
    echo "  tail -f /tmp/{conductor,fps,qrs,ic}.log"
    exit 1
fi