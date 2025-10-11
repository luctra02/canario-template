FROM caddy:2-alpine

# Copy website
COPY site /usr/share/caddy

# Inject environment variables from .env
COPY .env /tmp/.env
RUN source /tmp/.env && \
    sed -i "s|__GITLAB_API_URL__|$GITLAB_API_URL|g" /usr/share/caddy/index.html && \
    sed -i "s|__GITLAB_ACCESS_TOKEN__|$GITLAB_ACCESS_TOKEN|g" /usr/share/caddy/index.html && \
    sed -i "s|__FEATURE_FLAG_NAME__|$FEATURE_FLAG_NAME|g" /usr/share/caddy/index.html

HEALTHCHECK --interval=5s --timeout=3s --retries=3 \
  CMD wget -qO- http://localhost:80/ || exit 1
