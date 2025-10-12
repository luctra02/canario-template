# Use Caddy as base image
FROM caddy:2-alpine

# Copy the static website into Caddy's default web root
COPY site /usr/share/caddy

# Copy environment variables file
COPY .env /tmp/.env

# Inject environment variables into the HTML
RUN set -a && \
    . /tmp/.env && \
    set +a && \
    sed -i "s|__FLAG_PROXY_URL__|${FLAG_PROXY_URL}|g" /usr/share/caddy/index.html && \
    sed -i "s|__FEATURE_FLAG_NAME__|${FEATURE_FLAG_NAME}|g" /usr/share/caddy/index.html

# Add a basic healthcheck to ensure Caddy is serving content
HEALTHCHECK --interval=5s --timeout=3s --retries=3 \
  CMD wget -qO- http://localhost:80/ || exit 1