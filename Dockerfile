FROM node:20.16.0-bookworm-slim

# git: tags + history for `quark-scripts prod-publish` (map diff between tags).
# Optional: add `awscli` if your pipeline needs AWS CLI in this layer.
RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/app

# Nx must not try to start the daemon in Docker.
ENV NX_DAEMON=false

# Match the scaffold’s pinned pnpm (see PACKAGE_MANAGER_PIN in this repo).
RUN corepack enable && corepack prepare pnpm@9.14.2 --activate

# Copy the full workspace. Include `.git` in the build context when you need prod-publish
# (e.g. `docker build --progress=plain .` from a clone with tags).
# Private registry installs: provide `.npmrc` (and/or `.env`) in the context — they are gitignored by default;
# use CI secrets, BuildKit `--secret`, or `docker compose` `env_file` as appropriate.
COPY . .

RUN if [ -f .npmrc ]; then echo "Using project .npmrc"; else echo "No .npmrc in context — private installs may fail without registry auth"; fi

RUN pnpm install --frozen-lockfile || pnpm install

RUN pnpm run build:all

RUN echo "Git tags (for prod-publish):" && (git tag --sort=-creatordate 2>/dev/null | head -20 || true)

# Publishes changed packages from `.release/map.json` between the two latest tags (see `quark-scripts prod-publish`).
# Uses `DEV_REGISTRY_URL` / `PROD_REGISTRY_URL` (and related vars) from `.env` when present.
RUN pnpm exec quark-scripts prod-publish || echo "⚠️ prod-publish skipped or failed (e.g. fewer than two tags, no map diff, or registry auth)."

EXPOSE 6006

# Storybook lives at `apps/storybook`; path filter avoids relying on the package `name` field.
WORKDIR /usr/src/app
CMD ["pnpm", "--filter", "./apps/storybook", "run", "storybook"]
