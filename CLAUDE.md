# OrbGuard Monorepo

- `app/` — Flutter app (formerly the standalone `orbguard` repo). App-specific instructions,
  including the iOS 26 Liquid Glass theme specs, live in `app/CLAUDE.md`.
- `backend/` — Go backend (formerly `orbguard.lab`): chi API under `backend/internal/api/`,
  deploy manifests under `backend/deploy/`.

Run Flutter commands from `app/`, Go/make commands from `backend/`.

## CI/CD

- `.github/workflows/deploy.yml` deploys `backend/` to Azure Container Apps (container app
  `orbguard-lab`, resource group `ORB`) on pushes to `main` touching `backend/**`.
- `.github/workflows/app-ci.yml` runs Flutter analyze/test and the API contract gate:
  `python3 app/tools/check_api_contract.py --lab-root backend` (from repo root).
- Workflow files inside `app/.github/` or `backend/.github/` are inert — GitHub only runs
  workflows from the root `.github/workflows/`.

## History

Both original repos were merged with move-commits (no history rewrite): pre-monorepo SHAs
are still valid ancestors. Use `git log --follow` across the `app/`/`backend/` moves.
