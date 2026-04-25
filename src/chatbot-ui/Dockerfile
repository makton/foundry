# ── Stage 1: Build React app ───────────────────────────────────────────────────
FROM node:20-alpine AS builder

WORKDIR /build

COPY package*.json ./
RUN npm ci

COPY index.html vite.config.js ./
COPY src/ ./src/
RUN npm run build
# dist/ now contains production-ready static assets

# ── Stage 2: Serve with Nginx ──────────────────────────────────────────────────
FROM nginx:1.27-alpine

# Remove default config; replace with our SPA config
RUN rm /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/conf.d/default.conf

COPY --from=builder /build/dist /usr/share/nginx/html

# Run as non-root: redirect pid file to /tmp (writable by nginx user)
RUN chown -R nginx:nginx /usr/share/nginx/html \
 && sed -i 's|/var/run/nginx.pid|/tmp/nginx.pid|g' /etc/nginx/nginx.conf \
 && sed -i '/^user /d' /etc/nginx/nginx.conf

# entrypoint.sh generates /usr/share/nginx/html/env-config.js from env vars at
# container startup, then execs nginx. Must be chmod'd before switching to nginx user.
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER nginx

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget -qO- http://localhost:8080/health || exit 1

ENTRYPOINT ["/entrypoint.sh"]
