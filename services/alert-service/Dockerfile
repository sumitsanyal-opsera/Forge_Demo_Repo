# Alert Service — multi-stage Dockerfile
# Build context: repository root  (docker build -f services/alert-service/Dockerfile .)
#
# Security properties:
#   - Distroless runtime (no shell, no package manager)
#   - Non-root user UID 1000
#   - No secrets baked in — all sensitive values injected via environment at runtime
#   - Read-only root filesystem enforced via Kubernetes securityContext at deploy time

# ── Stage 1: Install dependencies ────────────────────────────────────────────
FROM node:20-alpine AS deps
WORKDIR /app

COPY package.json package-lock.json ./
COPY packages/shared/package.json ./packages/shared/
COPY services/alert-service/package.json ./services/alert-service/

RUN npm ci --ignore-scripts

# ── Stage 2: Compile TypeScript ───────────────────────────────────────────────
FROM deps AS builder
WORKDIR /app

COPY tsconfig.base.json ./
COPY packages/shared/tsconfig.json ./packages/shared/
COPY services/alert-service/tsconfig.json ./services/alert-service/

COPY packages/shared/src/ ./packages/shared/src/
COPY packages/shared/prisma/ ./packages/shared/prisma/
COPY services/alert-service/src/ ./services/alert-service/src/

RUN npx prisma generate --schema=packages/shared/prisma/schema.prisma

RUN npx tsc --build packages/shared
RUN npx tsc --build services/alert-service

RUN npm prune --omit=dev

# ── Stage 3: Production runtime ───────────────────────────────────────────────
FROM gcr.io/distroless/nodejs20-debian12 AS production
WORKDIR /app

COPY --from=builder /app/node_modules/ ./node_modules/

COPY --from=builder /app/packages/shared/dist/ ./packages/shared/dist/
COPY --from=builder /app/packages/shared/package.json ./packages/shared/

COPY --from=builder /app/services/alert-service/dist/ ./services/alert-service/dist/
COPY --from=builder /app/services/alert-service/package.json ./services/alert-service/

USER 1000

EXPOSE 3003

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD ["/nodejs/bin/node", "-e", \
    "require('http').get('http://localhost:3003/api/v1/health/live',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"]

CMD ["/app/services/alert-service/dist/index.js"]
