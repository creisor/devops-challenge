# syntax=docker/dockerfile:1

# ── Stage 1: install production dependencies ──────────────────────────────────
FROM node:22-alpine AS deps
WORKDIR /app

RUN corepack enable pnpm

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY prisma.config.ts ./
COPY prisma ./prisma

# prisma.config.ts calls env("POSTGRES_PRISMA_URL") at load time (even during
# `prisma generate`). A placeholder is sufficient — no DB connection is made.
ARG POSTGRES_PRISMA_URL=postgresql://placeholder:placeholder@localhost:5432/placeholder
ENV POSTGRES_PRISMA_URL=${POSTGRES_PRISMA_URL}

RUN pnpm install --frozen-lockfile --prod

# ── Stage 2: build ────────────────────────────────────────────────────────────
FROM node:22-alpine AS builder
WORKDIR /app

RUN corepack enable pnpm

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY prisma.config.ts ./
COPY prisma ./prisma

ARG POSTGRES_PRISMA_URL=postgresql://placeholder:placeholder@localhost:5432/placeholder
ENV POSTGRES_PRISMA_URL=${POSTGRES_PRISMA_URL}

# Install all deps (including dev) so prisma generate and next build work
RUN pnpm install --frozen-lockfile

COPY . .

RUN pnpm build

# ── Stage 3: runtime ──────────────────────────────────────────────────────────
FROM node:22-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3000

# Upgrade Alpine packages to pick up latest security patches, then create non-root user
# Enable pnpm via corepack so the migration job can run `pnpm db:migrate:deploy`
RUN apk upgrade --no-cache && \
    addgroup --system --gid 1001 nodejs && \
    adduser  --system --uid 1001 nextjs && \
    corepack enable pnpm

# Copy standalone output (server.js + minimal node_modules)
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
COPY --from=builder --chown=nextjs:nodejs /app/public ./public

# Replace standalone's minimal node_modules with the full builder set so the
# prisma CLI (devDependency) is available for `pnpm db:migrate:deploy`
COPY --from=builder --chown=nextjs:nodejs /app/node_modules ./node_modules

# package.json is required for pnpm to resolve script definitions
COPY --from=builder --chown=nextjs:nodejs /app/package.json ./package.json

# Full prisma directory: generated client, schema.prisma, and migrations/
# (prisma migrate deploy needs schema.prisma + migrations to run)
COPY --from=builder --chown=nextjs:nodejs /app/prisma ./prisma

# prisma.config.ts is read by the Prisma CLI at runtime to resolve the datasource URL
COPY --from=builder --chown=nextjs:nodejs /app/prisma.config.ts ./prisma.config.ts

USER nextjs

EXPOSE 3000

CMD ["node", "server.js"]
