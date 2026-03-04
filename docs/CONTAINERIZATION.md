# Inator Platform — Docker Containerization Spec

Specification for packaging all Inator Platform services into Docker containers
for consistent, reproducible development and production deployments.

## Decisions & Assumptions

- Scope: both dev and prod compose files
- Database (dev): SQLite per service
- Database (prod): SQLite per service (single-instance, low-traffic deployment)
- Dockerfile location: one `Dockerfile` per inator repo root
- Frontend (dev): Vite dev server container (hot reload)
- Frontend (prod): static build served directly by Caddy
- Django server: `runserver` in dev, Gunicorn in prod
- Caddy: runs as a container in both modes
- Secrets: `.env` files mounted/injected at runtime
- Inter-service networking: Docker Compose network with service-name DNS

---

## Overview

The platform currently runs as native processes orchestrated by `Taskfile.yml`.
This spec adds a Docker Compose layer on top of that, containerizing every
component while keeping the existing native workflow available.
### Workspace Prerequisite

The service repos are registered as **git submodules** of the `inator` platform
repo. A `git clone --recurse-submodules` automatically checks them out at the
correct paths (`./Authinator`, `./RMAinator`, `./Fulfilinator`), which is
exactly what the compose `build.context` values reference. No manual repo
cloning required.

### Services to Containerize

- `caddy` (ingress, reverse proxy)
- `frontend` (dev only runtime)
- `authinator` (Django backend)
- `rmainator` (Django backend)
- `fulfilinator` (Django backend)

No shared database container is required in this SQLite-first model.
Each backend owns its own SQLite file via named Docker volumes.

---

## Architecture

### Dev

```
Host :8080
    │
    ▼
┌─────────────────────────────────────────────┐
│  Docker network: inator-net                  │
│                                              │
│  caddy:8080 ──/api/auth/*──► authinator:8001 │
│              ──/api/rma/*──► rmainator:8002  │
│              ──/api/fulfil/*► fulfilinator:8003│
│              ──/*──────────► frontend:5173   │
│                                              │
│  SQLite volumes: authinator/rmainator/fulfil │
└─────────────────────────────────────────────┘
```

### Prod

```
Host :443 / :80
    │
    ▼
┌─────────────────────────────────────────────┐
│  Docker network: inator-net                  │
│                                              │
│  caddy:443  ──/api/auth/*──► authinator:8001 │
│             ──/api/rma/*──► rmainator:8002   │
│             ──/api/fulfil/*► fulfilinator:8003│
│             ──/*──────────► static /srv/www  │
│                                              │
│  SQLite volumes: authinator/rmainator/fulfil │
└─────────────────────────────────────────────┘
```

In production, this assumes a low-traffic single-instance deployment.

---

## Repository Changes

- `inator` repo:
  - `docker-compose.dev.yml`
  - `docker-compose.yml`
  - `Caddyfile.prod`
  - `Caddyfile.prod.Dockerfile`
  - Taskfile docker tasks
- `Authinator` repo:
  - `Dockerfile`
- `RMAinator` repo:
  - `Dockerfile`
- `Fulfilinator` repo:
  - `Dockerfile`
- `frontend/` in `inator` repo:
  - `Dockerfile` (dev runtime)

---

## File Specifications

### Per-Backend `Dockerfile` (same pattern for all three)

```dockerfile
# syntax=docker/dockerfile:1

FROM python:3.11-slim AS dev
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY backend/ ./backend/
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
EXPOSE 8001
CMD ["python", "backend/manage.py", "runserver", "0.0.0.0:8001"]

FROM python:3.11-slim AS prod
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt gunicorn
COPY backend/ ./backend/
RUN python backend/manage.py collectstatic --noinput
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 DJANGO_SETTINGS_MODULE=config.settings
EXPOSE 8001
CMD ["gunicorn", "--bind", "0.0.0.0:8001", "--workers", "2", "config.wsgi:application"]
```

Port differs by service (8001/8002/8003); Dockerfile pattern stays the same.

### `frontend/Dockerfile` (dev)

```dockerfile
FROM node:22-alpine AS dev
WORKDIR /app
COPY package*.json ./
RUN npm ci
EXPOSE 5173
CMD ["npx", "vite", "--host", "0.0.0.0", "--port", "5173", "--strictPort"]
```

### `docker-compose.dev.yml` (dev, SQLite)

```yaml
name: inator-dev
services:
  caddy:
    image: caddy:2-alpine
    ports:
      - "8080:8080"
    volumes:
      - ./Caddyfile.dev:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
    networks: [inator-net]
    depends_on: [authinator, rmainator, fulfilinator, frontend]

  frontend:
    build:
      context: ./frontend
      target: dev
    volumes:
      - ./frontend:/app
      - frontend_node_modules:/app/node_modules
    networks: [inator-net]
    environment:
      - CHOKIDAR_USEPOLLING=true

  authinator:
    build:
      context: ./Authinator   # assumes repo exists at platform root
      target: dev
    env_file: ./Authinator/backend/.env
    volumes:
      - ./Authinator/backend:/app/backend
      - authinator_data:/app/backend/data
    environment:
      - SQLITE_PATH=/app/backend/data/db.sqlite3
    networks: [inator-net]

  rmainator:
    build:
      context: ./RMAinator    # assumes repo exists at platform root
      target: dev
    env_file: ./RMAinator/backend/.env
    volumes:
      - ./RMAinator/backend:/app/backend
      - rmainator_data:/app/backend/data
    environment:
      - SQLITE_PATH=/app/backend/data/db.sqlite3
      - AUTHINATOR_API_URL=http://authinator:8001
    depends_on: [authinator]
    networks: [inator-net]

  fulfilinator:
    build:
      context: ./Fulfilinator # assumes repo exists at platform root
      target: dev
    env_file: ./Fulfilinator/backend/.env
    volumes:
      - ./Fulfilinator/backend:/app/backend
      - fulfilinator_data:/app/backend/data
    environment:
      - SQLITE_PATH=/app/backend/data/db.sqlite3
      - AUTHINATOR_API_URL=http://authinator:8001
    depends_on: [authinator]
    networks: [inator-net]

volumes:
  caddy_data:
  frontend_node_modules:
  authinator_data:
  rmainator_data:
  fulfilinator_data:

networks:
  inator-net:
    driver: bridge
```

### `docker-compose.yml` (prod, SQLite)

```yaml
name: inator
services:
  caddy:
    build:
      context: .
      dockerfile: Caddyfile.prod.Dockerfile
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - caddy_data:/data
      - caddy_config:/config
    depends_on: [authinator, rmainator, fulfilinator]
    networks: [inator-net]

  authinator:
    build:
      context: ./Authinator   # assumes repo exists at platform root
      target: prod
    env_file: ./Authinator/backend/.env.prod
    volumes:
      - authinator_data:/app/backend/data
    environment:
      - SQLITE_PATH=/app/backend/data/db.sqlite3
    networks: [inator-net]

  rmainator:
    build:
      context: ./RMAinator    # assumes repo exists at platform root
      target: prod
    env_file: ./RMAinator/backend/.env.prod
    volumes:
      - rmainator_data:/app/backend/data
    environment:
      - SQLITE_PATH=/app/backend/data/db.sqlite3
      - AUTHINATOR_API_URL=http://authinator:8001
    depends_on: [authinator]
    networks: [inator-net]

  fulfilinator:
    build:
      context: ./Fulfilinator # assumes repo exists at platform root
      target: prod
    env_file: ./Fulfilinator/backend/.env.prod
    volumes:
      - fulfilinator_data:/app/backend/data
    environment:
      - SQLITE_PATH=/app/backend/data/db.sqlite3
      - AUTHINATOR_API_URL=http://authinator:8001
    depends_on: [authinator]
    networks: [inator-net]

volumes:
  caddy_data:
  caddy_config:
  authinator_data:
  rmainator_data:
  fulfilinator_data:

networks:
  inator-net:
    driver: bridge
```

### `Caddyfile.prod.Dockerfile`

```dockerfile
FROM node:22-alpine AS frontend-build
WORKDIR /app
COPY frontend/package*.json ./
RUN npm ci
COPY frontend/ ./
RUN npm run build

FROM caddy:2-alpine
COPY Caddyfile.prod /etc/caddy/Caddyfile
COPY --from=frontend-build /app/dist /srv/www
```

### `Caddyfile.prod`

```caddy
{
    email {$CADDY_ACME_EMAIL}
}

{$DEPLOY_DOMAIN} {
    handle /api/auth/* { reverse_proxy authinator:8001 }
    handle /api/users/* { reverse_proxy authinator:8001 }
    handle /api/services/* { reverse_proxy authinator:8001 }
    handle /accounts/* { reverse_proxy authinator:8001 }
    handle /admin/* { reverse_proxy authinator:8001 }
    handle /api/rma/* { reverse_proxy rmainator:8002 }
    handle /api/fulfil/* { reverse_proxy fulfilinator:8003 }
    handle {
        root * /srv/www
        try_files {path} /index.html
        file_server
    }
}
```

---

## Django Configuration Changes Required

Use env-driven SQLite path so each container writes to its named volume.

Example `settings.py` change (all backends):

```python
from decouple import config
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
SQLITE_PATH = config("SQLITE_PATH", default=str(BASE_DIR / "db.sqlite3"))

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.sqlite3",
        "NAME": SQLITE_PATH,
    }
}
```

Also ensure `ALLOWED_HOSTS` includes the deployment domain and localhost values.

---

## New Taskfile Tasks (platform `Taskfile.yml`)

```yaml
docker:build:
  desc: Build all Docker images (dev targets)
  cmds:
    - docker compose -f docker-compose.dev.yml build

docker:up:
  desc: Start all services in Docker (dev mode)
  cmds:
    - docker compose -f docker-compose.dev.yml up

docker:down:
  desc: Stop and remove Docker containers (dev)
  cmds:
    - docker compose -f docker-compose.dev.yml down

docker:logs:
  desc: Tail logs from all Docker containers
  cmds:
    - docker compose -f docker-compose.dev.yml logs -f

docker:migrate:
  desc: Run migrations in all backend containers
  cmds:
    - docker compose -f docker-compose.dev.yml exec authinator python backend/manage.py migrate
    - docker compose -f docker-compose.dev.yml exec rmainator python backend/manage.py migrate
    - docker compose -f docker-compose.dev.yml exec fulfilinator python backend/manage.py migrate

docker:prod:build:
  desc: Build production images
  cmds:
    - docker compose build

docker:prod:up:
  desc: Start production stack
  cmds:
    - docker compose up -d

docker:prod:down:
  desc: Stop production stack
  cmds:
    - docker compose down
```

---

## Implementation Plan

### Phase 1: Per-Backend Dockerfiles

Goal: each inator repo has working `dev` and `prod` image targets.

Tasks:
- Add `Dockerfile` to Authinator
- Add `Dockerfile` to RMAinator
- Add `Dockerfile` to Fulfilinator
- Ensure each backend can use `SQLITE_PATH` from env

Acceptance:
- `docker build --target dev .` passes in each inator repo
- `docker build --target prod .` passes in each inator repo

### Phase 2: Frontend Dockerfile

Goal: unified frontend runs in container with hot reload.

Tasks:
- Add `frontend/Dockerfile`
- Ensure Vite binds to `0.0.0.0`

Acceptance:
- `docker build --target dev frontend/` passes

### Phase 3: Dev Compose

Goal: full stack boots via dev compose.

Tasks:
- Add `docker-compose.dev.yml`
- Update `Caddyfile.dev` upstreams to Docker service names
- Add docker tasks to platform `Taskfile.yml`
- Verify login + RMA + fulfil flows

Acceptance:
- `task docker:up` works
- `http://localhost:8080` serves app
- changes reload without rebuild for frontend/backends

### Phase 4: Prod Compose (SQLite)

Goal: production stack with Gunicorn + Caddy static frontend + SQLite volumes.

Tasks:
- Add `docker-compose.yml`
- Add `Caddyfile.prod`
- Add `Caddyfile.prod.Dockerfile`
- Add `.env.prod.example` for each backend
- Update `docs/DEPLOYMENT.md` with Docker prod path

Acceptance:
- `task docker:prod:up` works
- each service writes to its persistent SQLite volume
- frontend is static via Caddy

### Phase 5: Ops Guardrails

Tasks:
- Configure scheduled backups of SQLite volume data
- Add restore runbook
- Add monitoring for lock/contention and slow request patterns
- Define migration trigger thresholds to Postgres

Suggested triggers:
- sustained write lock errors
- need to run multiple backend replicas
- backup/restore RTO not acceptable

---

## Migration Notes

- `Caddyfile.dev` currently uses `localhost` backends; when Caddy runs in Docker,
  backend upstreams must be `authinator`, `rmainator`, `fulfilinator`.
- SQLite DB files must live on named volumes, not ephemeral container FS.
- Native task workflow stays available; Docker path is additive.

---

## Out of Scope

- CI/CD pipeline and registry publishing
- Kubernetes/Helm
- Managed secrets platform integration
- Any backend API changes

---

## Future Upgrade Path to Postgres

If traffic/operations outgrow SQLite, upgrade with minimal disruption:

1. Add `db` (Postgres) service to compose
2. Switch Django settings to env-driven engine (`DATABASE_URL`)
3. Migrate data service-by-service
4. Cut over one inator at a time

This keeps today’s implementation simple while preserving a clear growth path.
