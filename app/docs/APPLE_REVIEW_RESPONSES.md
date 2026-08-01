# App Review responses — OrbGuard (iOS + macOS)

Two automated App Review messages, with the reply to send and the code change
that backs it up. Both replies must also be pasted into
**App Store Connect → App Review Information → Notes**.

---

## 1. "An automated analysis indicates the app contains VPN functionality"

### Why it fired

It was our own fault, not a false positive on behaviour: the iOS app *declared*
VPN entitlements it never implemented.

`ios/Runner/Runner.entitlements` claimed `packet-tunnel-provider`, `dns-proxy`
and `app-proxy-provider`, plus Personal VPN
(`com.apple.developer.networking.vpn.api` = `allow-vpn`), and
`ios/Runner/Info.plist` declared `NEProviderClasses` naming
`DNSProxyProvider` and `PacketTunnelProvider`.

Verified against the project before changing anything:

- `DNSProxyProvider` does not exist anywhere in the repository.
- `PacketTunnelProvider.swift` and `VPNManager.swift` are compiled into **zero**
  targets — they are dead files, never built or shipped.
- No source in the Runner target references `NEVPNManager`,
  `NETunnelProviderManager` or `NEVPNProtocol`.
- The macOS target has no NetworkExtension or VPN entitlements at all, and no
  extension targets.

The only network extension OrbGuard actually ships is `OrbGuardFilter`, an
`NEFilterDataProvider` content filter that is configured through
`NEFilterManager` on MDM-supervised devices.

### Fix applied

Entitlements now list `content-filter-provider` only; the Personal VPN
entitlement and the whole `NEProviderClasses` dictionary are removed.

### Reply to send

> OrbGuard does not have VPN functionality on iOS or macOS, and it collects no
> user information via VPN.
>
> The automated analysis was triggered by stale entitlements in our project, not
> by app behaviour. Our iOS entitlements declared packet-tunnel, dns-proxy and
> app-proxy providers plus the Personal VPN entitlement, and Info.plist declared
> NEProviderClasses — but nothing implemented any of them. No shipping code
> references NEVPNManager or NETunnelProviderManager, and the classes named in
> NEProviderClasses either do not exist or are compiled into no target. We have
> removed all of them in this build. The macOS app has never declared any
> NetworkExtension or VPN entitlement.
>
> The only network extension OrbGuard ships is a content filter
> (NEFilterDataProvider, "OrbGuardFilter"), used solely to warn the user about
> malicious and fraudulent websites on MDM-supervised devices. It inspects
> destinations locally to decide allow/deny and does not record browsing history.
>
> Answering your questions directly:
>
> - What user information is the app collecting using VPN? None. There is no VPN.
> - For what purposes? Not applicable — no VPN data is collected.
> - Will the data be shared with any third parties? No. There is no VPN data to
>   share.
>
> For completeness: OrbGuard *detects* whether a VPN or proxy is already active
> on the device and reports that to the user as a security signal, and it can
> hand off to our separate OrbVPN app if the user chooses. Neither creates,
> configures or routes traffic through a VPN in this app.

---

## 2. "Does not include a functional link to the Terms of Use (EULA)"

### Why it fired

The App Description linked `https://orbvpn.com/terms` — our own service terms.
For auto-renewable subscriptions App Review requires a link to the **Terms of
Use (EULA)**: either Apple's standard EULA linked from the description, or a
custom EULA registered in App Store Connect.

### Fix applied

`APP_STORE_LISTING.md` now carries Apple's standard EULA link alongside the
existing legal links:

```
Terms of Use (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Terms of Service: https://orbvpn.com/terms
Privacy Policy: https://orbvpn.com/privacy
```

**This must be applied to the live App Description in App Store Connect** — it is
metadata, so it does not ship in a binary.

Alternative if our own terms should govern instead: paste
`https://orbvpn.com/terms` into App Store Connect → App Information → License
Agreement as a custom EULA. Do one or the other, not neither.

### Reply to send

> Thank you — corrected. OrbGuard uses Apple's standard Terms of Use (EULA), and
> we have added a functional link to it in the App Description:
> https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
>
> The subscription terms in the description already state the plan names,
> duration, that payment is charged to the Apple Account at confirmation, and
> that subscriptions auto-renew unless turned off at least 24 hours before the
> end of the period. The Terms of Use and Privacy Policy are also reachable
> in-app from the subscription screen itself.

---

## Also corrected in this pass

The iOS description advertised an **ON-DEVICE FIREWALL** ("blocks known
malicious, tracking and surveillance domains", "live blocked today counter").
That is Android-only — it is implemented by `OrbFirewallVpnService.kt` /
`FirewallChannelHandler.kt`, which have no iOS counterpart; iOS has only the
MDM-scoped content filter. Advertising it on the App Store listing is a
Guideline 2.3.1 accurate-metadata risk, so the section has been removed from
`APP_STORE_LISTING.md`.

The Scam Text Filter claim is accurate on iOS and stays — it is a real
`MessageFilterExtension` in the `OrbGuardSmsFilter` target.
