# OrbGuard Lab backend — security notes

This file is the operator-facing record of how the backend authenticates
callers, how the admin credential is protected and rotated, and what must never
land in this (public) repository. The code it describes lives in
`internal/api/middleware/auth.go`, `internal/api/router.go` and
`internal/api/handlers/yara.go`.

## 1. Credential layers

| Layer | Carried in | Issued by | Grants |
|-------|-----------|-----------|--------|
| Device API key / session token | `Authorization: Bearer <token>` | `POST /api/v1/auth/device` (anonymous), `POST /api/v1/auth/refresh` | Everything under `/api/v1` that is not admin-gated |
| OrbNet account JWT | `Authorization: Bearer <jwt>` | OrbNet (shared HS256 secret `ORBNET_JWT_ACCESS_SECRET`) | Same as a device key, plus device-ownership actions for that account |
| Service secret | `Authorization: Bearer <secret>` | Static (`ORBGUARD_JWT_SECRET`) | Service-to-service calls |
| Admin token | `X-Admin-Token: <token>` **in addition to** a bearer credential | Static (`ORBGUARD_ADMIN_TOKEN`) | `/api/v1/admin/*` and the admin-gated YARA mutations |

A device key costs nothing to obtain: anyone can `POST /api/v1/auth/device` with
a fresh `device_id`. Anything a device key can reach is therefore public
functionality, and must be designed as such (bounded input, no global side
effects). Global side effects require the admin token.

## 2. The admin token (`ORBGUARD_ADMIN_TOKEN`)

### What the server enforces

- **Header only.** The token is read from `X-Admin-Token` and nowhere else. A
  token in a query string or a request body is ignored (query strings end up in
  access logs, proxies and browser history). Tested in
  `internal/api/middleware/auth_admin_test.go`.
- **Strength check at startup.** `ConfigureAdminAuth` refuses a token that is
  unset, shorter than 32 characters, or one of the known placeholders
  (`dev-admin-token`, `changeme`, `admin`). A refused token is logged at ERROR
  (`reason` only, never the value) and admin routes answer
  `403 {"error":"admin access is not configured"}` exactly as if nothing were
  configured. The rest of the API keeps serving. Generate real values with
  `openssl rand -base64 48`.
- **Constant-time compare.** `crypto/subtle.ConstantTimeCompare`.
- **Per-address lockout.** Five wrong tokens from one client address within 15
  minutes lock that address out of every admin route — the correct token
  included — with `429 Too Many Requests` and a `Retry-After` header. Each
  further failure re-arms the 15-minute window; a successful call resets the
  counter. Refusing the correct token while locked is deliberate: a lock that
  still compared tokens would tell a guesser which guess was right, so it
  would not slow guessing at all.
  - *Which address.* The client as the Container Apps ingress saw it, never a
    header the client wrote. When the TCP peer is our own infrastructure (the
    ingress connects from private or RFC 6598 `100.64.0.0/10` addresses), it
    is the right-most public hop of `X-Forwarded-For`: the ingress appends the
    address it accepted the connection from, so anything the client sent sits
    to the left of it. When the peer is a public address, it is the peer.
    `X-Real-IP` and `True-Client-IP` are ignored. IPv6 clients are counted per
    `/64`. This resolved address is the `remote_ip` in the audit and failure
    logs.
  - *Storage.* Redis key `<redis.key_prefix>auth:admin:fail:<address>`
    (`orbguard:` is the default prefix; an IPv6 key names the `/64`), INCR and
    EXPIRE in one MULTI/EXEC. A counter found without an expiry is deleted and
    logged, never treated as a lock that lasts forever.
  - *Check after a deploy.* The `remote_ip` of your own first admin call must
    be your public address. If it shows an internal address instead, the
    ingress in front of the app is not appending to `X-Forwarded-For` as
    described, and every caller would share one counter.
  - *Redis down.* The lockout **fails open** to the normal 403 path and logs a
    WARN (`admin lockout store unavailable`): an outage must neither admit a
    wrong token nor shut operators out.
  - *Shared addresses.* Everyone behind one NAT or VPN egress shares a counter,
    so five wrong tokens from that egress lock all of them out for 15 minutes.
    Deleting the key in Redis lifts a lock early.

  The lockout is defence in depth; the token's length is the primary defence.
- **Audit log.** Every call that passes the admin check writes one line with
  `component=admin-audit`: `method`, `path`, `user_id` (session token),
  `device_id` (device key), `orbnet_user_id` (OrbNet account JWT, `0` for
  other credentials), `service` (bool, service secret), `remote_ip`, `status`,
  `duration`. The token is never logged; failed attempts log only the
  presented token's length.

### Rotation procedure (Azure Container App `orbguard-lab`, resource group `ORB`)

The value is held as the Container Apps secret `orbguard-admin-token` and the
container reads it through `ORBGUARD_ADMIN_TOKEN=secretref:orbguard-admin-token`
(the `secretref:` form keeps the value out of `az containerapp show` output and
out of the revision template).

**Order matters: set and verify the new value in Azure first, push code
afterwards.** A push to `main` that touches `backend/` deploys on its own
(`.github/workflows/deploy.yml`), and nothing that describes the admin surface
should go out while an exposed value still works.

1. Generate the new value into a file only you can read, never onto the
   terminal or into shell history, and copy it into the operator password
   manager before going on, so a half-finished rotation never leaves you not
   knowing what was set:
   ```bash
   umask 077
   TOKEN_FILE=$(mktemp)
   openssl rand -base64 48 | tr -d '\n' > "$TOKEN_FILE"
   ```
2. Store it as the Container Apps secret, point the env var at it and **force
   a new revision**. A replica reads secrets when it starts: changing the
   secret's value does not reach replicas already running, and an update that
   leaves the template unchanged (the `secretref:` line is already in place on
   every rotation after the first) creates no revision, so the old token would
   stay live. A new `--revision-suffix` changes the template:
   ```bash
   az containerapp secret set -n orbguard-lab -g ORB \
     --secrets "orbguard-admin-token=$(cat "$TOKEN_FILE")" -o none
   az containerapp update -n orbguard-lab -g ORB \
     --set-env-vars "ORBGUARD_ADMIN_TOKEN=secretref:orbguard-admin-token" \
     --revision-suffix "rot$(date -u +%Y%m%d%H%M)" \
     --query "properties.latestRevisionName" -o tsv
   ```
   The printed revision name must end in the `rot…` suffix just given.
   Restarting the active revision (`az containerapp revision restart`) also
   makes its replicas load the new value.
3. Wait for the new revision to serve (`curl -fsS https://<fqdn>/health`), then
   verify with a throwaway device key: the **old** token must get `403` and the
   **new** one `200` on `GET /api/v1/admin/stats/detailed`. If the new value is
   too short the startup log says so with a `reason`, and the routes are then
   disabled, not open.
   ```bash
   BASE=https://<fqdn>
   KEY=$(curl -fsS -X POST "$BASE/api/v1/auth/device" -H 'content-type: application/json' \
     -d '{"device_id":"rotation-check","platform":"test","device_name":"rotation-check"}' | jq -r '.api_key // .token')
   curl -s -o /dev/null -w '%{http_code}\n' "$BASE/api/v1/admin/stats/detailed" \
     -H "Authorization: Bearer $KEY" -H "X-Admin-Token: $(cat "$TOKEN_FILE")"
   ```
   Checking the old value counts as a wrong token for your address: four are
   safe, the fifth locks you out for 15 minutes.
4. Once the value is in the password manager, delete the file
   (`rm "$TOKEN_FILE"`), record the rotation date with the operator's
   credential records, and update every other holder of the old value
   (password manager entries, CI secrets). Never put it in a `.env*` file
   inside a repository checkout.

Rotate immediately whenever the value may have been exposed: committed to any
repository, even briefly (git history keeps it; deleting the file in a later
commit does not remove it), pasted into a ticket or chat, shown in a screen
share, or logged by a proxy. An exposed value is burned and must never be
reused.

## 3. Nothing from `.env*` is ever committed

`backend/.gitignore` ignores `.env`, `.env.*` and `*.env`, with only
`.env.example` exempt. The example file holds placeholders exclusively. Before
pushing, `git status --ignored backend` must list any local env file under
"Ignored files"; if a real value ever shows up in `git diff --cached`, abort
the commit and rotate the value — removing it in a later commit does not remove
it from history.

## 4. YARA rule permission model

The YARA engine's rule set is **global**: a rule added, deleted or reloaded
applies to every scan for every OrbGuard user. Mutating it is therefore admin
only, while reading and scanning stay open to any bearer credential.

| Operation | Paths | Required |
|-----------|-------|----------|
| Scan (`/scan`, `/scan/apk`, `/scan/ipa`, `/quick-scan`) | `POST /api/v1/yara/...` | bearer credential |
| Read rules and metadata | `GET /api/v1/yara/rules`, `GET /api/v1/yara/rules/{id}`, `GET /api/v1/yara/categories`, `GET /api/v1/yara/stats` | bearer credential |
| Validate a rule without storing it | `POST /api/v1/yara/parse` | bearer credential |
| Submit a rule for review (stored as `pending`, inert until approved) | `POST /api/v1/yara/submit` | bearer credential |
| Add / delete a rule, reload the engine | `POST /api/v1/yara/rules`, `DELETE /api/v1/yara/rules/{id}`, `POST /api/v1/yara/reload` and the canonical `POST /api/v1/admin/yara/rules`, `DELETE /api/v1/admin/yara/rules/{id}`, `POST /api/v1/admin/yara/reload` | bearer credential **+** `X-Admin-Token` |
| Review submissions | `GET /api/v1/admin/yara/submissions`, `POST .../{id}/approve`, `POST .../{id}/reject` | bearer credential **+** `X-Admin-Token` |

The original `/yara/rules` and `/yara/reload` paths were kept, admin-gated, so
that no client receives a 404; the `/admin/yara/...` paths are the canonical
ones. The mobile app only reads rules and scans.

Inputs that stay reachable with a device key are bounded:

| Endpoint | Body cap | Compile bound |
|----------|----------|---------------|
| `POST /yara/parse`, `POST /yara/submit` | 256 KiB | At most 1,024 patterns per rule and 64 KiB per pattern; each regex pattern at most 65,536 regexp instructions and all regex patterns of one submission at most 262,144 together, estimated from the parse before anything compiles. A breach is a validation error (`/parse`: `200` with `"valid":false`, `/submit`: `422`), never compiled. A 5 s deadline, checked between rule blocks and between patterns, is the backstop (`400 rule validation timed out`). |
| `POST /yara/scan`, `/scan/apk`, `/scan/ipa`, `/quick-scan` | 64 MiB | — |

Over the body cap the answer is `413`: a declared `Content-Length` above it is
refused before any of the body is read, and a body of unknown length is cut
off at the cap. The instruction budget exists because bytes do not bound a
regex: a counted repetition multiplies, so `/x{1000}/` is 7 bytes and 1,000
instructions, and 230 KB of such patterns used to cost seconds of CPU and
gigabytes of memory per request. With the budget, a maximal submission costs
well under a second.

Tests pinning this model run against the real route table:
`internal/api/router_yara_security_test.go`.

## 5. Reporting a vulnerability

Email support@orbvpn.com (the contact published in the Terms of Service) with
"security" in the subject. Do not open a public issue for anything that could be
exploited before it is fixed.
