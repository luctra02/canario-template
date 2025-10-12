FROM caddy:2-alpine
COPY site /usr/share/caddy

COPY flag-proxy/.env /tmp/.env
RUN sed -i "s|__FLAG_PROXY_URL__|${FLAG_PROXY_URL}|g" /usr/share/caddy/index.html \
 && sed -i "s|__FEATURE_FLAG_NAME__|${FEATURE_FLAG_NAME}|g" /usr/share/caddy/index.html

HEALTHCHECK --interval=5s --timeout=3s --retries=3 \
  CMD wget -qO- http://localhost:80/ || exit 1
