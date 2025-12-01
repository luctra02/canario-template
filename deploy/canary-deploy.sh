#!/bin/bash
set -e

BACKEND_NAME=$1
NEW_SERVER=$2
OLD_SERVER=$3
PROJECT_NAME=$4
NEW_PORT=$5
OLD_PORT=$6
SOCKET=$7
BACKEND_FILE=$8

LOG_FILE="/home/ubuntu/logs/${PROJECT_NAME}_canary.log"

# Lock file to ensure only one canary rollout runs at a time for this project
LOCKFILE="/tmp/${PROJECT_NAME}_canary.lock"
exec 9>"$LOCKFILE"
flock -n 9 || { echo "[$(date)] Another canary rollout is already running for ${PROJECT_NAME}. Waiting..." | tee -a "$LOG_FILE"; flock 9; }
echo "[$(date)] Lock acquired for canary rollout." | tee -a "$LOG_FILE"

# Apply live HAProxy commands
  echo "add server ${BACKEND_NAME}/${NEW_SERVER} 127.0.0.1:${NEW_PORT} check" | sudo socat stdio $SOCKET
  echo "enable server ${BACKEND_NAME}/${NEW_SERVER}" | sudo socat stdio $SOCKET
  echo "set server ${BACKEND_NAME}/${OLD_SERVER} weight 100" | sudo socat stdio $SOCKET

# Update old server weight
  if ! grep -q "server ${OLD_SERVER} " "$BACKEND_FILE"; then
  echo "    server ${OLD_SERVER} 127.0.0.1:${OLD_PORT} check weight 100" \
    | sudo tee -a "$BACKEND_FILE" > /dev/null
  else
    sudo sed -i "s/^ *server ${OLD_SERVER} .*/    server ${OLD_SERVER} 127.0.0.1:${OLD_PORT} check weight 100/" "$BACKEND_FILE"
  fi

  # Add new server to backend config
  if ! grep -q "server ${NEW_SERVER} " "$BACKEND_FILE"; then
    echo "    server ${NEW_SERVER} 127.0.0.1:${NEW_PORT} check" \
      | sudo tee -a "$BACKEND_FILE" > /dev/null
  else
    sudo sed -i "s/^ *server ${NEW_SERVER} .*/    server ${NEW_SERVER} 127.0.0.1:${NEW_PORT} check/" "$BACKEND_FILE"
  fi

# Rollout stages % weight for new server
STAGES=(10 30 60 100)
SLEEP_DURATION=60   # time to wait between stages in seconds

for WEIGHT in "${STAGES[@]}"; do
  NEW_WEIGHT=$WEIGHT
  OLD_WEIGHT=$((100 - WEIGHT))

  echo "[$(date)] Adjusting traffic: new=${NEW_WEIGHT}%, old=${OLD_WEIGHT}%" | tee -a "$LOG_FILE"

  # Update HAProxy weights dynamically
  echo "set server ${BACKEND_NAME}/${NEW_SERVER} weight ${NEW_WEIGHT}" | sudo socat stdio $SOCKET
  echo "set server ${BACKEND_NAME}/${OLD_SERVER} weight ${OLD_WEIGHT}" | sudo socat stdio $SOCKET

  # Adjust weights in backend file
  sudo sed -i "s/^ *server ${NEW_SERVER} .*/    server ${NEW_SERVER} 127.0.0.1:${NEW_PORT} check weight ${NEW_WEIGHT}/" "$BACKEND_FILE"
  sudo sed -i "s/^ *server ${OLD_SERVER} .*/    server ${OLD_SERVER} 127.0.0.1:${OLD_PORT} check weight ${OLD_WEIGHT}/" "$BACKEND_FILE"


  sleep $SLEEP_DURATION
done

# Once rollout is complete, disable and remove old version
echo "[$(date)] Canary rollout complete. Removing old server ${OLD_SERVER}" | tee -a "$LOG_FILE"

echo "set server ${BACKEND_NAME}/${OLD_SERVER} state maint" | sudo socat stdio $SOCKET
echo "del server ${BACKEND_NAME}/${OLD_SERVER}" | sudo socat stdio $SOCKET

docker stop "${OLD_SERVER}" 2>/dev/null || true
docker rm "${OLD_SERVER}" 2>/dev/null || true

sudo sed -i "/server ${OLD_SERVER} /d" "$BACKEND_FILE"
echo "[$(date)] Canary rollout finished successfully." | tee -a "$LOG_FILE"

# Release the lock
flock -u 9
