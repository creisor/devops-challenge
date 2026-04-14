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

# Create non-root user
RUN addgroup --system --gid 1001 nodejs && \
    adduser  --system --uid 1001 nextjs

# Copy standalone output
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
COPY --from=builder --chown=nextjs:nodejs /app/public ./public

# Prisma generated client is not included in standalone output — copy explicitly
COPY --from=builder --chown=nextjs:nodejs /app/prisma/generated ./prisma/generated

USER nextjs

EXPOSE 3000

CMD ["node", "server.js"]
