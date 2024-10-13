# syntax=docker/dockerfile:1

ARG NODE_VERSION=22.9.0
ARG NODE_VERSION_DESCRIPTOR=bookworm-slim as base
FROM node:${NODE_VERSION}-${NODE_VERSION_DESCRIPTOR} AS base
ENV PNPM_HOME=/pnpm
ENV PATH="$PNPM_HOME:$PATH"
ENV HOME=/usr/src
WORKDIR ${HOME}/app

# Update apt-get before installing packages & dumb-init
RUN apt-get update && apt-get install -y --no-install-recommends dumb-init

# Enable corepack in order to install pnpm globally
RUN corepack enable && corepack install -g pnpm@9.11.0 

#default to 3000 for node, you can add 9229 and 9230 (tests) for debug
ENV PORT=3000
EXPOSE $PORT
RUN --mount=type=bind,source=package.json,target=package.json \
    --mount=type=bind,source=pnpm-lock.yaml,target=pnpm-lock.yaml \
    --mount=type=bind,source=.npmrc,target=.npmrc 

FROM base AS dev
# Create bind mounts for pnpm build files & create cache mount for pnpm and install pnpm dependencies
RUN --mount=type=cache,id=pnpm,target=/.pnpm/store \
    pnpm install --frozen-lockfile
USER node
COPY --chown=node:node . .
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["pnpm", "dev"]

FROM base AS prod
RUN --mount=type=cache,id=pnpm,target=/.pnpm/store \
    pnpm install --frozen-lockfile --prod
USER node
COPY --chown=node:node . .
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["node", "src/index.js"]

FROM base AS test
RUN --mount=type=cache,id=pnpm,target=/.pnpm/store \
    pnpm install --frozen-lockfile
USER node
COPY --chown=node:node . .
RUN pnpm test

FROM base AS ci
RUN --mount=type=cache,id=pnpm,target=/.pnpm/store \
    pnpm fetch \
    && pnpm install --frozen-lockfile \
    && pnpm build \
    && pnpm test
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["node", "src/index.js"]