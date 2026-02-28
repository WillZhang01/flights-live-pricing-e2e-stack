#!/bin/bash
# Build all services with local proto dependencies
# Run this after updating proto schemas before starting the local stack

set -e

PARENT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "======================================"
echo "Building All Services (with proto)"
echo "======================================"
echo ""
echo "This will:"
echo "  1. Clean each service"
echo "  2. Regenerate proto classes"
echo "  3. Build the service"
echo "  4. Publish to Maven Local (~/.m2/repository)"
echo ""
echo "Build order: IC → QRS → FPS → Conductor"
echo ""

read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

echo ""

# Build ItineraryConstruction
echo "[1/4] Building ItineraryConstruction..."
cd "$PARENT_DIR/itinerary-construction"
./gradlew clean generateProto build publishToMavenLocal
if [ $? -eq 0 ]; then
    echo "      ✓ IC built successfully"
else
    echo "      ✗ IC build failed"
    exit 1
fi

echo ""

# Build QuoteRetrievalService
echo "[2/4] Building QuoteRetrievalService..."
cd "$PARENT_DIR/quoteretrievalservice"
./gradlew clean generateProto build publishToMavenLocal
if [ $? -eq 0 ]; then
    echo "      ✓ QRS built successfully"
else
    echo "      ✗ QRS build failed"
    exit 1
fi

echo ""

# Build FlightsPricingSvc
echo "[3/4] Building FlightsPricingSvc..."
cd "$PARENT_DIR/flights-pricing-svc"
./gradlew clean generateProto build publishToMavenLocal
if [ $? -eq 0 ]; then
    echo "      ✓ FPS built successfully"
else
    echo "      ✗ FPS build failed"
    exit 1
fi

echo ""

# Build Conductor
echo "[4/4] Building Conductor..."
cd "$PARENT_DIR/conductor"
./gradlew clean generateProto build publishToMavenLocal
if [ $? -eq 0 ]; then
    echo "      ✓ Conductor built successfully"
else
    echo "      ✗ Conductor build failed"
    exit 1
fi

echo ""
echo "======================================"
echo "✓ All services built successfully!"
echo "======================================"
echo ""
echo "Local Maven artifacts published to:"
echo "  ~/.m2/repository/net/skyscanner/"
echo ""
echo "Next steps:"
echo "  1. Start Redis: redis-server --port 6380 &"
echo "  2. Start stack: local-testing/start-local-stack.sh"
echo "  3. Test: See local-testing/README.md"
echo ""