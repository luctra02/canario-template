#!/bin/bash
set -e

IMAGE_TAG=$1
PROJECT_NAME=${CI_PROJECT_NAME:-canario}
CONTAINER_NAME="${PROJECT_NAME,,}"

# Assign default ports (if not provided)
PORT_OLD=${PORT_OLD:-8080}
PORT_NEW=${PORT_NEW:-8081}

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
docker run -d --name "${CONTAINER_NAME}-${TARGET_PORT}" -p $TARGET_PORT:8080 "$IMAGE_TAG"

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
    server ${CONTAINER_NAME}-old 127.0.0.1:${PORT_OLD} check inter 5s rise 2 fall 5
    server ${CONTAINER_NAME}-new 127.0.0.1:${PORT_NEW} check inter 5s rise 2 fall 5
EOF

  echo "Reloading HAProxy..."
  sudo systemctl reload haproxy
  echo "HAProxy backend created for ${CONTAINER_NAME}"
else
  echo "Existing HAProxy backend detected for ${CONTAINER_NAME}. Skipping creation."
fi

# Stop old container
docker stop "${CONTAINER_NAME}-${ACTIVE_PORT}" 2>/dev/null || true
docker rm "${CONTAINER_NAME}-${ACTIVE_PORT}" 2>/dev/null || true

echo "Deployment complete for $PROJECT_NAME — now serving on port $TARGET_PORT"
