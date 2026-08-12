# Detection Service — multi-stage Dockerfile
# Build context: repository root  (docker build -f services/detection-service/Dockerfile .)
#
# Security properties:
#   - Distroless runtime (no shell, no package manager)
#   - Non-root user UID 1000
#   - No secrets baked in — all sensitive values injected via environment at runtime
#   - Read-only root filesystem enforced via Kubernetes securityContext at deploy time

# ── Stage 1: Install dependencies ────────────────────────────────────────────
FROM node:20-alpine AS deps
WORKDIR /app

# Copy workspace manifests first — Docker cache layer avoids reinstall unless
# a package.json changes
COPY package.json package-lock.json ./
COPY packages/shared/package.json ./packages/shared/
COPY services/detection-service/package.json ./services/detection-service/

# --ignore-scripts prevents execution of arbitrary postinstall scripts.
# Prisma generate is invoked explicitly after install.
RUN npm ci --ignore-scripts

# ── Stage 2: Compile TypeScript ───────────────────────────────────────────────
FROM deps AS builder
WORKDIR /app

# TypeScript configuration
COPY tsconfig.base.json ./
COPY packages/shared/tsconfig.json ./packages/shared/
COPY services/detection-service/tsconfig.json ./services/detection-service/

# Source code
COPY packages/shared/src/ ./packages/shared/src/
COPY packages/shared/prisma/ ./packages/shared/prisma/
COPY services/detection-service/src/ ./services/detection-service/src/

# Generate Prisma client with correct binary target for distroless runtime
RUN npx prisma generate --schema=packages/shared/prisma/schema.prisma

# Compile shared package (detection-service tsconfig references it)
RUN npx tsc --build packages/shared

# Compile detection service
RUN npx tsc --build services/detection-service

# Remove devDependencies before copying to the runtime image
RUN npm prune --omit=dev

# ── Stage 3: Production runtime ───────────────────────────────────────────────
# gcr.io/distroless/nodejs20-debian12: Debian 12 base with only Node.js 20.
# No shell, no apt, no curl — significantly reduces the attack surface.
FROM gcr.io/distroless/nodejs20-debian12 AS production
WORKDIR /app

# Production node_modules (devDependencies already pruned in builder stage)
COPY --from=builder /app/node_modules/ ./node_modules/

# Compiled shared package output
COPY --from=builder /app/packages/shared/dist/ ./packages/shared/dist/
COPY --from=builder /app/packages/shared/package.json ./packages/shared/

# Compiled detection service output
COPY --from=builder /app/services/detection-service/dist/ ./services/detection-service/dist/
COPY --from=builder /app/services/detection-service/package.json ./services/detection-service/

# Non-root user — distroless accepts numeric UIDs without a named account
USER 1000

EXPOSE 3002

# Liveness and readiness probes — available at /api/v1/health/live and /api/v1/health/ready
# The node binary is at /nodejs/bin/node in gcr.io/distroless/nodejs20-debian12
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD ["/nodejs/bin/node", "-e", \
    "require('http').get('http://localhost:3002/api/v1/health/live',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"]

CMD ["/app/services/detection-service/dist/index.js"]
