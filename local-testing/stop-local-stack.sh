#!/bin/bash
# Stop all locally running services

echo "======================================"
echo "Stopping Local Full Stack"
echo "======================================"
echo ""

# Try to read PIDs from saved file
if [ -f /tmp/fps-stack-pids.txt ]; then
    PIDS=$(cat /tmp/fps-stack-pids.txt)
    echo "Found saved PIDs: $PIDS"
    echo ""

    for PID in $PIDS; do
        if ps -p $PID > /dev/null 2>&1; then
            echo "Stopping process $PID..."
            kill $PID
        else
            echo "Process $PID not running"
        fi
    done

    rm /tmp/fps-stack-pids.txt
    echo ""
    echo "✓ Stopped services from saved PIDs"
else
    echo "No saved PIDs found. Attempting to kill by process name..."
    echo ""

    # Kill any microservice-shell-java.jar processes
    pkill -f "microservice-shell-java.jar"

    if [ $? -eq 0 ]; then
        echo "✓ Stopped Java services"
    else
        echo "No Java services found running"
    fi
fi

echo ""
echo "Checking for remaining processes..."
REMAINING=$(pgrep -f "microservice-shell-java.jar" | wc -l)

if [ "$REMAINING" -eq 0 ]; then
    echo "✓ All services stopped"
else
    echo "⚠️  Found $REMAINING remaining processes"
    echo ""
    echo "To force kill:"
    echo "  pkill -9 -f 'microservice-shell-java.jar'"
fi

echo ""
echo "======================================"
echo "Logs preserved in /tmp/*.log"
echo "======================================"
echo "  /tmp/ic.log"
echo "  /tmp/qrs.log"
echo "  /tmp/fps.log"
echo "  /tmp/conductor.log"
echo ""
echo "To view logs:"
echo "  tail -f /tmp/{ic,qrs,fps,conductor}.log"
echo ""
echo "To clean logs:"
echo "  rm /tmp/{ic,qrs,fps,conductor}.log"
echo ""