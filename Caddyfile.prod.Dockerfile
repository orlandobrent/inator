# Stage 1: Build the unified frontend
FROM node:22-alpine AS frontend-build
WORKDIR /app
COPY frontend/package*.json ./
RUN npm ci
COPY frontend/ ./
RUN npm run build

# Stage 2: Caddy with static files baked in
FROM caddy:2-alpine
COPY Caddyfile.prod /etc/caddy/Caddyfile
COPY --from=frontend-build /app/dist /srv/www
