# Inator Family Rules

Standards and conventions for all inator microservices.

## Naming

- Service names MUST follow the pattern `<Domain>inator`:
  - Acronyms: `FOOinator` (e.g. `RMAinator`)
  - Words: `FooBarinator` (e.g. `Fulfilinator`, `Authinator`)
- The leading component is always capitalized — never all-lowercase (e.g. ~~authinator~~ → `Authinator`).
- Directory names match the service name exactly.
- Filenames within services use hyphens, not underscores (except where Django requires underscores).

## Architecture

The platform uses a **unified gateway architecture**:
- **Caddy** reverse proxy on `:8080` routes all traffic
- **Unified frontend** (`frontend/` at platform root) — single React SPA for all inator UIs
- Each inator provides a **backend only** — Django + DRF

Each inator directory contains:
- `backend/` — Django + Django REST Framework (settings in `config/`)
- `deft/` — Shared AI agent framework (Deft)
- `Taskfile.yml` — Task runner (replaces Makefile)
- `docs/` — External-facing documentation (screenshots, guides); committed to git
- `Reference/` — Internal dev materials (spreadsheets, specs, mockups); gitignored, never committed

### Port Assignments

Each inator backend MUST have a unique port. The gateway and unified frontend are managed at the platform level.

| Service              | Port  | Notes                        |
|----------------------|-------|------------------------------|
| Caddy Gateway        | 8080  | Single entry point           |
| Unified Frontend     | 5173  | Vite dev server              |
| Authinator backend   | 8001  | `/api/auth`, `/api/users`    |
| RMAinator backend    | 8002  | `/api/rma`                   |
| Fulfilinator backend | 8003  | `/api/fulfil`                |

New inators increment from the highest assigned backend port.

### Inter-Service Communication

- Services communicate via REST APIs over HTTP.
- Use environment variables for service URLs (e.g. `AUTHINATOR_API_URL`).
- Never hardcode service hostnames or ports.

## Tech Stack

### Backend
- **Framework**: Django 6.x + djangorestframework
- **Auth**: djangorestframework-simplejwt, django-allauth (via Authinator)
- **Python**: 3.11+
- **Deps**: `requirements.txt` (pip) — one per service
- **DB**: SQLite for dev, plan for Postgres in prod
- **Lint**: `ruff check .`
- **Format**: `black .`
- **Test**: `pytest` with `pytest-django`, `coverage` (≥75% threshold)

### Frontend
- **Language**: TypeScript (strict mode) — no `.js`/`.jsx` source files
- **Build**: Vite
- **Styling**: Tailwind CSS
- **Package manager**: npm
- **Lint**: `npm run lint` (ESLint with `typescript-eslint` parser)
- **Typecheck**: `npm run typecheck` (`tsc --noEmit`)
- **Test**: `npm test` (when configured)

#### TypeScript Requirements
- `tsconfig.json` MUST set `"strict": true`
- `any` types are FORBIDDEN — use `unknown` for type-safe unknowns
- All component props, state, and API responses MUST be explicitly typed
- A `typecheck` script MUST exist in `package.json`
- ESLint MUST be configured with `typescript-eslint` for `.ts`/`.tsx` files

## Taskfile

Every inator MUST have a `Taskfile.yml` with at minimum these tasks:
- `backend:install`, `backend:dev`, `backend:test`, `backend:lint`, `backend:fmt`
- `frontend:install`, `frontend:dev`, `frontend:build`, `frontend:lint`, `frontend:typecheck`
- `install`, `dev`, `test`, `lint`, `fmt` (combined)
- `test:coverage` (with threshold enforcement)

The `PROJECT_NAME` var in Taskfile.yml MUST match the service directory name.

## Secrets

- All secrets in `secrets/` dir as `.env` files, never in code.
- `.env` at service root for local dev (gitignored).
- `.env.example` checked in with placeholder values.
- Use `python-decouple` for env var loading in Django.

## SCM

- The `inator/` platform repo is the parent git repository.
- Each inator backend is a **git submodule** inside it (its own independent GitHub repo).
- Clone everything with: `git clone --recurse-submodules https://github.com/losomode/inator.git`
- Update all submodules after pulling: `git submodule update --init --recursive`
- Conventional Commits: `type(scope): description`
  - Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `perf`, `ci`, `build`, `revert`

## Creating a New Inator

1. Create directory `<name>inator/` under this root.
2. Scaffold `backend/` with Django + DRF.
3. Add a frontend module in the unified SPA (`frontend/src/modules/<name>/`).
4. Copy and adapt `Taskfile.yml` from an existing inator.
5. Copy `deft/` framework from an existing inator.
6. Assign the next available backend port.
7. Add a route block in `Caddyfile.dev` for the new API prefix.
8. Create `.env.example`, `.gitignore`, `README.md`.
9. Initialize git repo.
10. Update the port table in this file.

## Quality Gates

Before any commit:
- `task lint` passes
- `task test` passes
- `task test:coverage` meets threshold (≥75%)
- No secrets in tracked files
- Files SHOULD be < 500 lines, MUST be < 1000 lines
