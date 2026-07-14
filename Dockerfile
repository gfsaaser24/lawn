# syntax=docker/dockerfile:1

# ---- Build stage ----
FROM oven/bun:1.3.6 AS build
WORKDIR /app

# Install dependencies first (better layer caching)
COPY package.json bun.lock ./
RUN bun install --frozen-lockfile

# Copy the rest of the source
COPY . .

# Vite inlines VITE_* at build time. Provide defaults so the image builds
# standalone; Coolify build args override these.
ARG VITE_CONVEX_URL=https://lawn-cvx.chipone.ai
ARG VITE_CLERK_PUBLISHABLE_KEY=pk_test_aW1wcm92ZWQtZ25hdC01MS5jbGVyay5hY2NvdW50cy5kZXYk
ENV VITE_CONVEX_URL=$VITE_CONVEX_URL
ENV VITE_CLERK_PUBLISHABLE_KEY=$VITE_CLERK_PUBLISHABLE_KEY

RUN bun run build

# ---- Runtime stage ----
FROM nginx:alpine AS runtime

# Static client build (SPA + prerendered marketing pages)
COPY --from=build /app/dist/client /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
