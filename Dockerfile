# Build Node image
FROM node:20-alpine

WORKDIR /app

# Copy package files and install dependencies
COPY package.json ./
RUN npm install --production

# Copy backend logic and static files
COPY server/server.js .
COPY site ./site

# Expose port (used internally by HAProxy)
EXPOSE 8080

# Start server
CMD ["node", "server.js"]
