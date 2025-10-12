FROM node:20-alpine

# Set working directory
WORKDIR /app

# Copy your flag-proxy script
COPY flag-proxy.js .

# Initialize a small package.json and install dependencies
RUN npm init -y \
 && npm pkg set type=module \
 && npm install express node-fetch

# Expose port 9000 (internal, used by HAProxy)
EXPOSE 9000

# Start the flag proxy
CMD ["node", "flag-proxy.js"]
