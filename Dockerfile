# Multi-stage Dockerfile for opsera-stuck-pipeline-detection services.
#
# Build a specific service:
#   docker build --build-arg SERVICE_NAME=api-gateway -t opsera/api-gateway:latest .
#
# Security properties:
#   - Distroless base image (no shell, no package manager, minimal attack surface)
#   - Non-root user UID 1001
#   - Read-only filesystem enforced at runtime via Kubernetes:
#       securityContext:
#         readOnlyRootFilesystem: true
#         runAsNonRoot: true
#         runAsUser: 1001
#   - Target image size: <150MB

# ── Stage 1: Dependency installation ─────────────────────────────────────────
FROM node:20-alpine AS deps
ARG SERVICE_NAME=api-gateway
WORKDIR /workspace

# Copy all workspace manifests first for Docker layer cache efficiency.
# Reinstallation only triggers when a package.json changes, not on source changes.
COPY package.json package-lock.json ./
COPY packages/shared/package.json ./packages/shared/
COPY services/api-gateway/package.json ./services/api-gateway/
COPY services/alert-service/package.json ./services/alert-service/
COPY services/baseline-service/package.json ./services/baseline-service/
COPY services/dashboard-service/package.json ./services/dashboard-service/
COPY services/detection-service/package.json ./services/detection-service/

# Install all dependencies (devDependencies required for TypeScript compilation).
# --ignore-scripts prevents execution of arbitrary postinstall scripts.
RUN npm ci --ignore-scripts

# ── Stage 2: TypeScript compilation ───────────────────────────────────────────
FROM deps AS builder
ARG SERVICE_NAME=api-gateway
WORKDIR /workspace

# Copy TypeScript configuration
COPY tsconfig.base.json ./
COPY packages/shared/tsconfig.json ./packages/shared/
COPY services/api-gateway/tsconfig.json ./services/api-gateway/
COPY services/alert-service/tsconfig.json ./services/alert-service/
COPY services/baseline-service/tsconfig.json ./services/baseline-service/
COPY services/dashboard-service/tsconfig.json ./services/dashboard-service/
COPY services/detection-service/tsconfig.json ./services/detection-service/

# Copy source code
COPY packages/shared/src/ ./packages/shared/src/
COPY packages/shared/prisma/ ./packages/shared/prisma/
COPY services/ ./services/

# Compile shared package first (services depend on its type declarations)
RUN npx tsc --build packages/shared

# Compile the target service
RUN npx tsc --build services/${SERVICE_NAME}

# Prune devDependencies — production image only needs runtime dependencies
RUN npm prune --omit=dev

# ── Stage 3: Production image ─────────────────────────────────────────────────
# gcr.io/distroless/nodejs20-debian12: minimal Debian 12 image with only Node.js.
# No shell, no apt, no curl — significantly reduces the attack surface.
FROM gcr.io/distroless/nodejs20-debian12 AS production
ARG SERVICE_NAME=api-gateway
WORKDIR /app

# Copy production node_modules (devDependencies already pruned in builder stage)
COPY --from=builder /workspace/node_modules/ ./node_modules/

# Copy compiled shared package output and its manifest (workspace resolution)
COPY --from=builder /workspace/packages/shared/dist/ ./packages/shared/dist/
COPY --from=builder /workspace/packages/shared/package.json ./packages/shared/

# Copy compiled service output and its manifest
# Default: api-gateway. Rebuild with --build-arg SERVICE_NAME=<service> for others.
COPY --from=builder /workspace/services/api-gateway/dist/ ./services/api-gateway/dist/
COPY --from=builder /workspace/services/api-gateway/package.json ./services/api-gateway/

# Non-root user UID 1001 per security policy.
# Distroless images accept numeric UIDs without requiring a named user account.
USER 1001

# Read-only filesystem is enforced at runtime (Kubernetes securityContext), not here.
# Volumes for writable paths (e.g. /tmp) must be declared explicitly in the Pod spec.

EXPOSE 3000

# Entrypoint: distroless nodejs images expect the path to the compiled JS module.
# The distroless runtime prepends `node` to this command automatically.
CMD ["/app/services/api-gateway/dist/index.js"]
