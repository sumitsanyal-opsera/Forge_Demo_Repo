# Opsera Stuck Pipeline Detection System

Automatically identifies Salesforce CI/CD pipelines that exceed expected execution times and alerts engineers proactively — eliminating the need to manually monitor deployments across multiple orgs.

## Architecture

The system is structured as an **npm workspaces monorepo** with four bounded-context microservices, a shared infrastructure library, and a React dashboard (added in subsequent work orders).

```
opsera-stuck-pipeline-detection/
├── packages/
│   └── shared/            # @opsera/shared — shared infrastructure (DB, logging, errors, validation)
└── services/
    ├── api-gateway/       # @opsera/api-gateway — TLS termination, RBAC, rate limiting, routing
    ├── baseline-service/  # @opsera/baseline-service — P50/P90/P99 EWMA baseline computation
    ├── detection-service/ # @opsera/detection-service — stuck-pipeline state machine
    ├── alert-service/     # @opsera/alert-service — email notification dispatch
    └── dashboard-service/ # @opsera/dashboard-service — metrics aggregation for the React SPA
```

## Prerequisites

- **Node.js** ≥ 20
- **npm** ≥ 10 (workspaces support)
- **Docker** + **Docker Compose** (for local PostgreSQL 16 and Redis 7)

## Quick Start

### 1. Install dependencies

```bash
npm install
```

### 2. Configure environment

```bash
cp .env.example .env
# Edit .env with your local values (DATABASE_URL, REDIS_URL, etc.)
```

### 3. Start the database and Redis

```bash
docker compose up -d
# Wait for containers to be healthy:
docker compose ps
```

### 4. Set up the database

```bash
cd packages/shared
npx prisma generate      # Generate the Prisma client
npx prisma migrate dev   # Create the initial migration
cd ../..
```

### 5. Build all packages

```bash
npm run build
```

### 6. Run tests

```bash
npm test
```

## Development

### Useful scripts (run from repo root)

| Command | Description |
|---|---|
| `npm run build` | Compile all workspaces |
| `npm run lint` | Run ESLint across all TypeScript files |
| `npm run format` | Format all files with Prettier |
| `npm run format:check` | Check formatting without writing |
| `npm test` | Run all workspace test suites |
| `npm run typecheck` | TypeScript type-check without emitting |

### Adding a dependency to a specific workspace

```bash
npm install <package> --workspace=packages/shared
npm install <package> --workspace=services/baseline-service
```

## Infrastructure

### PostgreSQL 16

- Port: `5432`
- Database: `opsera_stuck_pipeline`
- Connection pool: 20 connections per service instance (via `connection_limit` URL parameter)
- Migrations: `packages/shared/prisma/migrations/`
- See `packages/shared/prisma/MIGRATION_PATTERNS.md` for the hybrid Prisma + raw SQL approach used for partitioned tables.

### Redis 7

- Port: `6379`
- Purpose: active detection state cache (24h TTL) + Redis Streams message broker

## Packages

### `@opsera/shared`

Shared infrastructure library imported by all services. Exports:

| Module | Exports |
|---|---|
| Database | `getPrismaClient`, `connectDatabase`, `disconnectDatabase`, `checkDatabaseHealth` |
| Logging | `createLogger`, `runWithCorrelationId`, `getCorrelationId`, `maskPii` |
| Errors | `AppError` hierarchy, `errorMiddleware`, `mapPrismaError`, `registerProcessHandlers` |
| Validation | `validate`, `validateBody`, `validateQuery`, `validateParams`, schema helpers |

## Environment Variables

See [`.env.example`](.env.example) for the full list with descriptions.

Key variables:

| Variable | Required | Description |
|---|---|---|
| `DATABASE_URL` | Yes | PostgreSQL connection string (include `connection_limit=20`) |
| `REDIS_URL` | Yes | Redis connection URL |
| `NODE_ENV` | Yes | `development` \| `test` \| `production` |
| `LOG_LEVEL` | No | `debug` \| `info` \| `warn` \| `error` (default: `info`) |

## Contributing

- TypeScript strict mode is enforced — no `any` types without explicit justification.
- All new code must pass `npm run lint` and `npm run typecheck`.
- Do not commit `.env` or any file containing real credentials.
- See `packages/shared/prisma/MIGRATION_PATTERNS.md` before writing database migrations.
