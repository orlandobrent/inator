# syntax=docker/dockerfile:1

FROM node:22-alpine AS dev

WORKDIR /app

COPY package*.json ./
RUN npm ci

# Source is volume-mounted in dev for hot reload
EXPOSE 5173

CMD ["npx", "vite", "--host", "0.0.0.0", "--port", "5173", "--strictPort"]
