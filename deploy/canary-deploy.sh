#!/bin/bash
set -e

BACKEND_NAME=$1
NEW_SERVER=$2
OLD_SERVER=$3
SOCKET="/run/haproxy/admin.sock"
LOG_FILE="/var/log/${BACKEND_NAME}_canary.log"

echo "[$(date)] Starting background canary rollout for ${BACKEND_NAME}" | tee -a "$LOG_FILE"


echo "[$(date)] Initial traffic split: new=10%, old=90%" | tee -a "$LOG_FILE"

# Rollout stages % weight for new server
STAGES=(30 60 100)
SLEEP_DURATION=60   # time to wait between stages in seconds

for WEIGHT in "${STAGES[@]}"; do
  NEW_WEIGHT=$WEIGHT
  OLD_WEIGHT=$((100 - WEIGHT))

  echo "[$(date)] Adjusting traffic: new=${NEW_WEIGHT}%, old=${OLD_WEIGHT}%" | tee -a "$LOG_FILE"

  # Update HAProxy weights dynamically
  echo "set server ${BACKEND_NAME}/${NEW_SERVER} weight ${NEW_WEIGHT}" | sudo socat stdio $SOCKET
  echo "set server ${BACKEND_NAME}/${OLD_SERVER} weight ${OLD_WEIGHT}" | sudo socat stdio $SOCKET

  sleep $SLEEP_DURATION
done

# Once rollout is complete, disable and remove old version
echo "[$(date)] Canary rollout complete — removing old server ${OLD_SERVER}" | tee -a "$LOG_FILE"

echo "set server ${BACKEND_NAME}/${OLD_SERVER} state maint" | sudo socat stdio $SOCKET
echo "del server ${BACKEND_NAME}/${OLD_SERVER}" | sudo socat stdio $SOCKET

docker stop "${OLD_SERVER}" 2>/dev/null || true
docker rm "${OLD_SERVER}" 2>/dev/null || true

echo "[$(date)] Canary rollout finished successfully." | tee -a "$LOG_FILE"
