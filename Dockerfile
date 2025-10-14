# --- Stage 1: Build Node image ---
FROM node:20-alpine

WORKDIR /app

# Copy backend logic and static files
COPY server/server.js .
COPY site ./site

# Install dependencies
RUN npm init -y \
 && npm pkg set type=module \
 && npm install express node-fetch

# Expose port (used internally by HAProxy)
EXPOSE 8080

# Start server
CMD ["node", "server.js"]
