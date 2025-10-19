#!/bin/bash
set -e

IMAGE_TAG=$1
PROJECT_NAME=$2
PORT_OLD=$3
PORT_NEW=$4
GITLAB_ACCESS_TOKEN=$5
PROJECT_ID=$6

CONTAINER_NAME="${PROJECT_NAME,,}"

echo "🚀 Deploying $PROJECT_NAME using old port $PORT_OLD and new port $PORT_NEW..."

# Pull the latest image
docker pull "$IMAGE_TAG"

# Detect active port (which container is live)
if docker ps --format '{{.Ports}}' | grep -q "$PORT_OLD->8080"; then
  ACTIVE_PORT=$PORT_OLD
  TARGET_PORT=$PORT_NEW
else
  ACTIVE_PORT=$PORT_NEW
  TARGET_PORT=$PORT_OLD
fi

echo "Active port: $ACTIVE_PORT | Deploying to port: $TARGET_PORT"

# Run new container
docker run -d \
  --name "${CONTAINER_NAME}-${TARGET_PORT}" \
  -p $TARGET_PORT:8080 \
  -e PROJECT_ID="${PROJECT_ID}" \
  -e GITLAB_ACCESS_TOKEN="${GITLAB_ACCESS_TOKEN}" \
  "$IMAGE_TAG"

# Health check
sleep 5
if curl -fs "http://localhost:$TARGET_PORT" > /dev/null; then
  echo "New version healthy on port $TARGET_PORT"
else
  echo "Health check failed on port $TARGET_PORT. Rolling back..."
  docker stop "${CONTAINER_NAME}-${TARGET_PORT}" && docker rm "${CONTAINER_NAME}-${TARGET_PORT}"
  exit 1
fi

# Create HAProxy backend config if missing
BACKENDS_DIR="/etc/haproxy/backends"
BACKEND_FILE="${BACKENDS_DIR}/${CONTAINER_NAME}.cfg"

if [ ! -f "$BACKEND_FILE" ]; then
  echo "No HAProxy backend found for $PROJECT_NAME. Creating one..."

  sudo mkdir -p "$BACKENDS_DIR"
  sudo bash -c "cat > $BACKEND_FILE" <<EOF
backend ${CONTAINER_NAME}_backend
    mode http
    balance roundrobin
    option httpchk GET /
    server ${CONTAINER_NAME}-old 127.0.0.1:${PORT_OLD} check
    server ${CONTAINER_NAME}-new 127.0.0.1:${PORT_NEW} check
EOF
fi

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


# Stop old container
docker stop "${CONTAINER_NAME}-${ACTIVE_PORT}" 2>/dev/null || true
docker rm "${CONTAINER_NAME}-${ACTIVE_PORT}" 2>/dev/null || true

echo "Deployment complete for $PROJECT_NAME — now serving on port $TARGET_PORT"
