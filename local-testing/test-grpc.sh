#!/bin/bash
# Test services via gRPC using grpcurl
# Install: brew install grpcurl

set -e

echo "============================================"
echo "gRPC Testing with grpcurl"
echo "============================================"
echo ""

# Check if grpcurl is installed
if ! command -v grpcurl &> /dev/null; then
    echo "❌ grpcurl is not installed"
    echo "Install with: brew install grpcurl"
    exit 1
fi

# Test FPS gRPC endpoint
echo "[1] Testing FPS gRPC Service..."
echo ""

# List available services
echo "Available services on FPS (localhost:50055):"
grpcurl -plaintext localhost:50055 list

echo ""
echo "Available methods:"
grpcurl -plaintext localhost:50055 list net.skyscanner.flightspricingsvc.FlightsPricingService

echo ""
echo "To make a create request:"
echo "grpcurl -plaintext -d @ localhost:50055 net.skyscanner.flightspricingsvc.FlightsPricingService/Create <<EOF"
echo "{"
echo "  \"query\": {"
echo "    \"market\": \"UK\","
echo "    \"locale\": \"en-GB\","
echo "    \"currency\": \"GBP\","
echo "    \"adults\": 1"
echo "  }"
echo "}"
echo "EOF"

echo ""
echo "============================================"
echo "Note: grpcurl works with JSON and converts to protobuf"
echo "This is easier than protobuf text format for manual testing"
echo "============================================"
