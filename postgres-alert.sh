#!/bin/bash
# Separate bash file, neet to run in background

# Configuration
LOG_FILE="/var/log/postgresql/postgresql-18-main.log"
WEBHOOK_URL=""

echo "Starting PostgreSQL connection monitor..."

# Continuously read new lines added to the log file
tail -F "$LOG_FILE" | while read -r LOG_LINE
do
    # Check if the log line contains a successful connection authorization
    if [[ "$LOG_LINE" == *"connection authorized:"* ]]; then

        # Extract user and database details from the log line
        TIMESTAMP=$(echo "$LOG_LINE" | awk '{print $1 " " $2 " " $3}')
        DETAILS=$(echo "$LOG_LINE" | awk -F "connection authorized: " '{print $2}')
        PAYLOAD=" { \"content\": \"New connection at $TIMESTAMP: $DETAILS\" }"

        echo "[ALERT] $TIMESTAMP - $DETAILS"

        if [ -n "$PAYLOAD" ] ; then
            curl -X POST -H 'Content-Type: application/json' -d "$PAYLOAD" "$WEBHOOK_URL"
        fi
    fi
done
