# OrbGuard Monorepo

OrbGuard mobile-security product — Flutter app and Go backend in one repository.

| Directory  | What it is                                                    | Formerly                     |
| ---------- | ------------------------------------------------------------- | ---------------------------- |
| `app/`     | Flutter application (iOS / Android / desktop / web)           | `orbvpn/OrbGuard`            |
| `backend/` | Go backend (chi API, aggregator, DNS canary; Azure deploy)    | `orbvpn/orbguard.lab`        |

Full commit history of both original repositories is preserved (grafted, not rewritten —
pre-monorepo commit SHAs remain valid ancestors). Use `git log --follow` to trace a file
across the move into its subdirectory.

## CI/CD (`.github/workflows/`)

- `deploy.yml` — builds `backend/` into a Docker image and deploys to Azure Container Apps.
  Triggers on pushes to `main` that touch `backend/**`, and on manual dispatch.
- `app-ci.yml` — Flutter analyze + test for `app/`, plus the app↔backend API contract gate
  (`app/tools/check_api_contract.py`), which now always runs since both sides live here.

## Development

```sh
# App
cd app && flutter pub get && flutter run

# Backend
cd backend && make build   # or: go test ./...

# API contract gate (app calls vs backend routes)
python3 app/tools/check_api_contract.py --lab-root backend
```
