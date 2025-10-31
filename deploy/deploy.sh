#!/bin/bash
set -e

MODE=${1:-standard}
MODE=${MODE,,} 
IMAGE_TAG=$2
PROJECT_NAME=$3
GITLAB_ACCESS_TOKEN=$4
PROJECT_ID=$5

PROJECT_NAME=${PROJECT_NAME,,}
CONTAINER_NAME="${PROJECT_NAME}-${IMAGE_TAG##*:}"

if docker ps --format '{{.Names}}' | grep -q "$CONTAINER_NAME"; then
  echo "Version $IMAGE_TAG is already deployed and running. Skipping redeploy."
  exit 0
fi

echo "Deploying $PROJECT_NAME using $MODE strategy"


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
    http-request replace-path ^/${PROJECT_NAME}/?(.*)$ /\1
EOF

  # Create HAProxy frontend rule if missing
  ROUTE_NAME=${6:-$PROJECT_NAME}
  FRONTENDS_DIR="/etc/haproxy/frontends"
  FRONTEND_FILE="${FRONTENDS_DIR}/${PROJECT_NAME}.cfg"

  if [ ! -f "$FRONTEND_FILE" ]; then
    echo "No HAProxy frontend rule found for $PROJECT_NAME. Creating one..."
    sudo mkdir -p "$FRONTENDS_DIR"
    sudo bash -c "cat > $FRONTEND_FILE" <<EOF
    acl path_${ROUTE_NAME} path_beg /${ROUTE_NAME}
    use_backend ${BACKEND_NAME} if path_${ROUTE_NAME}
EOF
  fi

  LOCKFILE="/tmp/haproxy_config.lock"
  exec 9>$LOCKFILE
  flock -n 9 || { echo "Another deployment is updating HAProxy config. Waiting..."; flock 9; }
# Combine base config file + all backend files
  sudo bash -c 'cat /etc/haproxy/haproxy.base \
                    /etc/haproxy/frontends/*.cfg \
                    /etc/haproxy/backends/*.cfg \
               > /etc/haproxy/haproxy.cfg'

  # Validate and reload
  if sudo haproxy -c -f /etc/haproxy/haproxy.cfg; then
    echo "HAProxy config valid. Reloading..."
    sudo systemctl reload haproxy
  else
    echo "Invalid HAProxy config. Aborting reload."
    flock -u 9
    exit 1
  fi
  flock -u 9
fi

# Add the new server in the correct backends file
if ! grep -q "$CONTAINER_NAME" "$BACKEND_FILE"; then
  echo "    server ${CONTAINER_NAME} 127.0.0.1:${TARGET_PORT} check weight 100" | sudo tee -a "$BACKEND_FILE" > /dev/null
fi

# Check if old server exists
OLD_SERVER=$(echo "show servers state" | sudo socat stdio $SOCKET \
  | grep "${BACKEND_NAME}" | grep -v "${CONTAINER_NAME}" | awk '{print $4}' | head -n1)

#Canary deployment
if [ "$MODE" = "canary" ] && [ -n "$OLD_SERVER" ]; then

  echo "Triggering background progressive rollout..."
  echo "add server ${BACKEND_NAME}/${CONTAINER_NAME} 127.0.0.1:${TARGET_PORT} check weight 10" | sudo socat stdio $SOCKET
  echo "enable server ${BACKEND_NAME}/${CONTAINER_NAME}" | sudo socat stdio $SOCKET
  echo "set server ${BACKEND_NAME}/${OLD_SERVER} weight 90" | sudo socat stdio $SOCKET
  nohup bash /home/ubuntu/canario-template/deploy/canary-deploy.sh \
    "$BACKEND_NAME" "$CONTAINER_NAME" "$OLD_SERVER" > /var/log/${PROJECT_NAME}_canary.log 2>&1 &

  echo "Canary rollout started in background, pipeline will now exit."
  exit 0

# Standard deployment
else
  echo "add server ${BACKEND_NAME}/${CONTAINER_NAME} 127.0.0.1:${TARGET_PORT} check weight 100" | sudo socat stdio $SOCKET
  echo "enable server ${BACKEND_NAME}/${CONTAINER_NAME}" | sudo socat stdio $SOCKET

  if [ -n "$OLD_SERVER" ]; then
    echo "Removing old server $OLD_SERVER..."
    echo "set server ${BACKEND_NAME}/${OLD_SERVER} state maint" | sudo socat stdio $SOCKET
    echo "del server ${BACKEND_NAME}/${OLD_SERVER}" | sudo socat stdio $SOCKET
    sudo sed -i "/server ${OLD_SERVER}/d" "$BACKEND_FILE"
    docker stop "${OLD_SERVER}" 2>/dev/null || true
    docker rm "${OLD_SERVER}" 2>/dev/null || true
  fi
fi

echo "Deployment complete for $PROJECT_NAME — now serving on port $TARGET_PORT"
