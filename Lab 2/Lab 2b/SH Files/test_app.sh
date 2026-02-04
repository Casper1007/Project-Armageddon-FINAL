#!/bin/bash
# Quick test script for EC2 → RDS Lab application

EC2_IP="54.91.122.42"
MAX_ATTEMPTS=30
ATTEMPT=0

echo "Waiting for application to be ready..."

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    echo "Attempt $((ATTEMPT+1))/$MAX_ATTEMPTS..."
    
    RESPONSE=$(curl -s -w "\n%{http_code}" http://"$EC2_IP"/ -m 5)
    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | head -1)
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo "✓ Application is responding!"
        echo ""
        echo "=== ROOT ENDPOINT RESPONSE ==="
        echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
        echo ""
        break
    fi
    
    ATTEMPT=$((ATTEMPT+1))
    sleep 5
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    echo "✗ Application did not respond after $((ATTEMPT * 5)) seconds"
    echo "This is normal if EC2 startup script is still running"
    exit 1
fi

# Test initialization
echo ""
echo "=== TESTING DATABASE INITIALIZATION ==="
INIT_RESPONSE=$(curl -s -X POST http://"$EC2_IP"/init)
echo "$INIT_RESPONSE" | jq . 2>/dev/null || echo "$INIT_RESPONSE"

# Test add note
echo ""
echo "=== TESTING ADD NOTE ==="
ADD_RESPONSE=$(curl -s "http://$EC2_IP/add?note=test_note_$(date +%s)")
echo "$ADD_RESPONSE" | jq . 2>/dev/null || echo "$ADD_RESPONSE"

# Test list notes
echo ""
echo "=== TESTING LIST NOTES ==="
LIST_RESPONSE=$(curl -s http://"$EC2_IP"/list)
echo "$LIST_RESPONSE" | jq . 2>/dev/null || echo "$LIST_RESPONSE"

echo ""
echo "✓ Application testing complete!"
