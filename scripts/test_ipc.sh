#!/usr/bin/env bash
set -euo pipefail

SOCKET="$HOME/.agentvibeisland/ipc.sock"

echo "=== Agent Vibe Island — IPC + UI Test ==="
echo ""

# Verify the socket exists
if [ ! -S "$SOCKET" ]; then
    echo "ERROR: Socket not found at $SOCKET"
    echo "Make sure the AgentVibeIsland app is running."
    exit 1
fi

echo "1. POST /register (claude)"
REGISTER=$(curl -s --unix-socket "$SOCKET" \
    -X POST http://localhost/register \
    -H "Content-Type: application/json" \
    -d '{"agent":"claude","agentLabel":"Claude (VS Code)","pid":12345}')
echo "   $REGISTER"

echo ""
echo "2. POST /status"
STATUS=$(curl -s --unix-socket "$SOCKET" \
    -X POST http://localhost/status \
    -H "Content-Type: application/json" \
    -d '{"agent":"claude","taskDescription":"Refactoring auth module","taskProgress":0.62}')
echo "   $STATUS"

echo ""
echo "3. POST /request (blocking — will wait for UI action)"
echo "   Sending permission request in background..."
echo "   >>> Hover over the notch wings or press ⌥Space to open the tray."
echo "   >>> Click Allow or Deny in the tray to continue."
echo ""

# Send request in background and capture result
TMPFILE=$(mktemp)
curl -s --unix-socket "$SOCKET" \
    -X POST http://localhost/request \
    -H "Content-Type: application/json" \
    -d '{
        "event":"permission_request",
        "agent":"claude",
        "requestId":"req_test_1",
        "action":"write_file",
        "actionLabel":"Write to file",
        "scope":"src/auth/middleware.ts",
        "taskDescription":"Refactoring auth module",
        "taskProgress":0.62,
        "workspacePath":"/Users/name/projects/my-app"
    }' > "$TMPFILE" &
CURL_PID=$!

# Wait for the user to action in UI (|| true to prevent set -e from killing us)
wait $CURL_PID || true
REQUEST=$(cat "$TMPFILE")
rm -f "$TMPFILE"

echo "   Response: $REQUEST"
if echo "$REQUEST" | grep -q '"decision"'; then
    DECISION=$(echo "$REQUEST" | python3 -c "import sys,json; print(json.load(sys.stdin)['decision'])" 2>/dev/null || echo "unknown")
    echo "   ✓ Decision received: $DECISION"
else
    echo "   ✗ Missing decision in response"
    exit 1
fi

echo ""
echo "4. POST /unregister"
UNREGISTER=$(curl -s --unix-socket "$SOCKET" \
    -X POST http://localhost/unregister \
    -H "Content-Type: application/json" \
    -d '{"agent":"claude","pid":12345}')
echo "   $UNREGISTER"

echo ""
echo "=== Test complete ==="
