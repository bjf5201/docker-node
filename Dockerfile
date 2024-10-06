# syntax=docker/dockerfile:1

# Base image for dev, build, test, and production stages
FROM mcr.microsoft.com/vscode/devcontainers/typescript-node:12 AS base
# Build steps
ENV PNPM_HOME=/pnpm
ENV PATH="$PNPM_HOME:$PATH"
ENV HOME=/usr/src
WORKDIR ${HOME}/app

# Install
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    dumb-init

# Enable corepack in order to install pnpm globally
RUN corepack enable && corepack install -g pnpm@9.11.0 

# Create a non-root user & reflect new user in PATH
ARG USERNAME=node
RUN groupadd --gid 1001 $USERNAME && \
    useradd --uid 1001 --gid $USERNAME -m $USERNAME
ENV PATH="/home/${USERNAME}/.local/bin:${PATH}"
USER ${USERNAME}


FROM base AS development
# Create bind mounts for pnpm build files & create cache mount for pnpm and install pnpm dependencies
RUN --mount=type=bind,source=package.json,target=package.json \
    --mount=type=bind,source=pnpm-lock.yaml,target=pnpm-lock.yaml \
    --mount=type=bind,source=.npmrc,target=.npmrc \
    --mount=type=cache,id=pnpm,target=/.pnpm/store \
    pnpm install --frozen-lockfile
USER ${USERNAME}
COPY --chown=${USERNAME}:${USERNAME} . .
ARG PORT=3000
EXPOSE $PORT
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["pnpm", "dev"]

FROM base AS build
RUN --mount=type=bind,source=package.json,target=package.json \
    --mount=type=bind,source=pnpm-lock.yaml,target=pnpm-lock.yaml \
    --mount=type=bind,source=.npmrc,target=.npmrc \
    --mount=type=cache,id=pnpm,target=/.pnpm/store pnpm install --frozen-lockfile --prod
USER ${USERNAME}
COPY --chown=${USERNAME}:${USERNAME} . .
RUN pnpm build

FROM node:20-bookworm-slim AS production
WORKDIR /usr/src/app
ARG USERNAME=node
COPY --chown=${USERNAME}:${USERNAME} --from=build /usr/src/app/dist ./dist
COPY --chown=${USERNAME}:${USERNAME} --from=build /usr/src/app/node_modules/ ./node_modules/
USER ${USERNAME}
# Default to 3000 for node, you can add 9229 and 9230 (tests) for debug
ENV PORT=3000
EXPOSE $PORT
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["node", "src/index.js"]

FROM development AS test
RUN pnpm test
