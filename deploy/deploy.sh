#!/bin/bash
set -e

IMAGE_TAG=$1
PROJECT_NAME=$2
GITLAB_ACCESS_TOKEN=$3
PROJECT_ID=$4

PROJECT_NAME=${PROJECT_NAME,,}
CONTAINER_NAME="${PROJECT_NAME}-${IMAGE_TAG##*:}"

if docker ps --format '{{.Names}}' | grep -q "$CONTAINER_NAME"; then
  echo "Version $IMAGE_TAG is already deployed and running. Skipping redeploy."
  exit 0
fi


# Pull the latest image
docker pull "$IMAGE_TAG"

# Run the new container on a random port
echo "Starting new container for $PROJECT_NAME..."
docker run -d -P \
  --name "$CONTAINER_NAME" \
  -e PROJECT_ID="${PROJECT_ID}" \
  -e GITLAB_ACCESS_TOKEN="${GITLAB_ACCESS_TOKEN}" \
  "$IMAGE_TAG"

TARGET_PORT=$(docker port "$CONTAINER_NAME" 8080/tcp | cut -d: -f2 | head -n1)
echo "Container started on host port $TARGET_PORT"

# Health check
sleep 5
if curl -fs "http://localhost:$TARGET_PORT" > /dev/null; then
  echo "New version healthy on port $TARGET_PORT"
else
  echo "Health check failed on port $TARGET_PORT. Rolling back..."
  docker stop "${CONTAINER_NAME}" && docker rm "${CONTAINER_NAME}"
  exit 1
fi

# Create HAProxy backend config if missing
BACKENDS_DIR="/etc/haproxy/backends"
BACKEND_FILE="${BACKENDS_DIR}/${PROJECT_NAME}.cfg"
SOCKET="/run/haproxy/admin.sock"
BACKEND_NAME="${PROJECT_NAME}_backend"

if [ ! -f "$BACKEND_FILE" ]; then
  echo "No HAProxy backend found for $PROJECT_NAME. Creating one..."
  sudo mkdir -p "$BACKENDS_DIR"
  sudo bash -c "cat > $BACKEND_FILE" <<EOF
backend ${BACKEND_NAME}
    mode http
    balance roundrobin
    option httpchk GET /
EOF

# Combine base config file + all backend files
  sudo bash -c 'cat /etc/haproxy/haproxy.base /etc/haproxy/backends/*.cfg > /etc/haproxy/haproxy.cfg'

  # Validate and reload
  if sudo haproxy -c -f /etc/haproxy/haproxy.cfg; then
    echo "HAProxy config valid. Reloading..."
    sudo systemctl reload haproxy
  else
    echo "Invalid HAProxy config. Aborting reload."
    exit 1
  fi
fi

# Add the new server in the correct backends file
if ! grep -q "$CONTAINER_NAME" "$BACKEND_FILE"; then
  echo "    server ${CONTAINER_NAME} 127.0.0.1:${TARGET_PORT} check" | sudo tee -a "$BACKEND_FILE" > /dev/null
fi


# Enable the new one
echo "add server ${BACKEND_NAME}/${CONTAINER_NAME} 127.0.0.1:${TARGET_PORT} check" | sudo socat stdio $SOCKET || true
echo "enable server ${BACKEND_NAME}/${CONTAINER_NAME}" | sudo socat stdio $SOCKET


# Delete old server from HAProxy and config if it exists
OLD_SERVER=$(echo "show servers state" | sudo socat stdio $SOCKET \
  | grep "${BACKEND_NAME}" | grep -v "${CONTAINER_NAME}" | awk '{print $4}' | head -n1)
if [ -n "$OLD_SERVER" ]; then
  echo "Disabling old server $OLD_SERVER..."
  echo "set server ${BACKEND_NAME}/${OLD_SERVER} state maint" | sudo socat stdio "$SOCKET"
  echo "del server ${BACKEND_NAME}/${OLD_SERVER}" | sudo socat stdio "$SOCKET"
  sudo sed -i "/server ${OLD_SERVER}/d" "$BACKEND_FILE"
fi

# Stop old container
docker stop "${OLD_SERVER}" 2>/dev/null || true
docker rm "${OLD_SERVER}" 2>/dev/null || true


echo "Deployment complete for $PROJECT_NAME — now serving on port $TARGET_PORT"
