FROM node:20-alpine

WORKDIR /app
COPY flag-proxy.js .
RUN npm init -y && npm i express node-fetch@2 && npm install cors
EXPOSE 9000
CMD ["node", "flag-proxy.js"]