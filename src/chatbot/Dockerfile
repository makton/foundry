# ── Stage 1: Build React client ────────────────────────────────────────────────
FROM node:20-alpine AS client-builder

WORKDIR /build

COPY client/package*.json ./client/
RUN npm --prefix client ci

COPY client/ ./client/
RUN npm --prefix client run build
# client/dist now contains the production static assets

# ── Stage 2: Production server ─────────────────────────────────────────────────
FROM node:20-alpine AS production

ENV NODE_ENV=production
ENV PORT=8080

WORKDIR /app

# Install server dependencies only (no dev deps)
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Copy server source
COPY server.js ./

# Copy built React assets from Stage 1 → served by Express as static files
COPY --from=client-builder /build/client/dist ./public

# Non-root user for security
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:8080/health || exit 1

CMD ["node", "server.js"]
