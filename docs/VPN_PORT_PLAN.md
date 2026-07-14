# OrbGuard VPN Integration — Port Plan (OrbVPN SmartConnect engine)

Status: **planning / Phase 1 scaffolding**. Owner: TBD. Created 2026-07-14.

## Goal

Give OrbGuard a real, working VPN with OrbVPN's **SmartConnect** auto-connect intelligence
(DPI-evasion, region-aware protocol fallback, on-device learning), so the VPN settings screen
(`app/lib/.../settings_screen.dart` → `VpnSettingsScreen`, keys `vpn_*`) becomes functional
instead of inert.

## The reality (why this is multi-week, not a toggle)

SmartConnect (in `/Users/nima/Developments/orbx.flutter/lib/core/smart_connect/`, ~5.4k LOC) is
only the **decision brain**. Every attempt it emits is executed by OrbVPN's hand-rolled native
tunnel engine:

| Layer | OrbVPN component | Portable as-is? |
| --- | --- | --- |
| Decision layer | `fallback_chain_generator`, `region_config`, `arm_bandit`, `connection_memory`, `connection_attempt/result` | ✅ pure Dart, liftable |
| Tunnel services | `WireGuardService`, `VlessService`, `OrbConnectService`, `SshService` | ⚠️ thin, but bind to native |
| iOS native | `ios/PacketTunnel/` Network Extension (~12k LOC Swift) + WireGuard/HevSocks5/Pi `.xcframework`s + `networkextension` entitlement + `group.com.orb.vpn` app group | ❌ heavy native |
| Android native | `OrbVpnService : VpnService` + `orbvless.aar` + WireGuard native tunnel | ❌ heavy native |
| Channel | `MethodChannel('com.orb.vpn/vpn')`, `.../split_tunneling`, `.../dns` | — |
| Backend | OrbNet `/smartconnect/hints`, `/telemetry`, `/health/{id}`, `/stats/{cc}` + server list + auth + subscription | ❌ OrbGuard has none of this |

**Hard prerequisite (decided):** OrbGuard has no VPN server fleet, so it will **reuse OrbVPN's
backend + servers** — OrbGuard embeds the OrbVPN client engine pointed at OrbNet. This couples
OrbGuard to OrbVPN auth/subscription/server-list, which must be resolved as a product/infra
task, not in app code.

## Non-code prerequisites (owner action — blockers for a working tunnel)

1. **Apple**: a provisioning profile + App ID (`com.orb.guard`) with the
   `com.apple.developer.networking.networkextension` (`packet-tunnel-provider`) capability, and a
   shared **App Group** (e.g. `group.com.orb.guard.vpn`) for the app ↔ extension.
2. **OrbVPN backend access**: OrbGuard devices must authenticate to OrbNet and be entitled to
   pull the server list + `/smartconnect/*` hints (subscription/identity model decision).
3. **Android**: `BIND_VPN_SERVICE` + the `orbvless.aar` / WireGuard native libs redistribution
   rights within OrbGuard's package.

## Phases

### Phase 0 — Decisions & access (owner)
- Confirm OrbGuard→OrbVPN auth/subscription/server-list reuse.
- Provision Apple NetworkExtension capability + App Group; Android VpnService rights.
- Exit criteria: OrbGuard can obtain an OrbVPN-authenticated server list in a test build.

### Phase 1 — Portable decision layer + app abstraction (code, verifiable now) ← START HERE
- Add `app/lib/services/vpn/`: a `VpnController` interface (`connect/disconnect/statusStream`,
  `VpnStatus`) so the app depends on an abstraction, not the engine.
- Port the pure-Dart decision layer (`fallback_chain_generator`, `region_config`, `arm_bandit`,
  `connection_memory`, `connection_attempt/result`) as a self-contained library with unit tests
  (no native, no backend — verifiable via `flutter test`).
- Interim `OrbVpnHandoffController`: opens/deep-links the OrbVPN app so the OrbGuard VPN screen
  does something honest **today** while the native engine lands. Wire `VpnSettingsScreen` to it.
- Exit criteria: `flutter analyze`/`test` green; VPN screen no longer inert.

### Phase 2 — Native tunnel: Android first (lower provisioning friction)
- Bring `OrbVpnService` (VpnService) + `orbvless.aar` + WireGuard native tunnel; wire
  `MethodChannel('com.orb.vpn/vpn')`; implement `AndroidVpnController`.
- Exit criteria: a real tunnel connects on an Android device via one protocol (WireGuard).

### Phase 3 — Native tunnel: iOS PacketTunnel
- Add the PacketTunnel Network Extension target + entitlements + App Group + WireGuard/HevSocks5
  xcframeworks; implement `IosVpnController`. Requires Phase 0 Apple provisioning.
- Exit criteria: a real tunnel connects on an iOS device.

### Phase 4 — Wire SmartConnect end-to-end
- Feed the ported decision layer with OrbNet `/smartconnect/hints`; drive the tunnel services
  through the fallback chain + on-device bandit; verify traffic after each attempt; report
  telemetry. Wire the `vpn_*` settings (auto-connect, kill-switch, preferred server, per-app).
- Exit criteria: auto-connect + fallback + kill-switch work on both platforms.

### Phase 5 — Backend (`/smartconnect/*` for OrbGuard)
- Either proxy OrbNet's endpoints or reuse them directly; add per-device health/telemetry.

## Verification note

Phases 2–5 require **physical devices + signing/provisioning** and cannot be verified in the
headless dev environment — they need on-device QA by the owner. Phase 1 is fully verifiable in CI.

## Interim (until Phase 2+)

Ship the Phase 1 `OrbVpnHandoffController` so the VPN screen is honest (hands off to OrbVPN)
rather than presenting dead auto-connect/kill-switch toggles.
