# Phase 9 — Physical Device Test Procedure

> The code side of Phase 9 is complete: join rate limiting, malformed-command
> handling, frame limits, protocol-version checks, recipient-specific
> projections and Host cleanup are in place and covered by the existing unit
> and widget tests.
>
> The acceptance criteria of PLAN.md §15 Phase 9 need **2–6 physical devices**
> on Android, iOS and mixed networks. This file is the checklist for that run.
> It has not been executed yet.

---

## 0. Prerequisites

- At least one Android and one iOS device on the same Wi-Fi.
- Release builds (`flutter build apk` / `flutter build ios`).
- Internet disabled on the router for the offline run.
- A packet capture tool on the Wi-Fi (optional, for the projection audit).

---

## 1. Security and protocol

| # | Step | Expected result |
|---|---|---|
| 1.1 | Send 6 wrong invitation codes from one client | The first 5 are rejected with `ROOM_CODE_INVALID`; the 6th closes the connection with `RATE_LIMITED` |
| 1.2 | Send an unknown protocol version | Rejected with `UNSUPPORTED_PROTOCOL_VERSION` |
| 1.3 | Send an oversized frame | Connection closes with `FRAME_TOO_LARGE` |
| 1.4 | Send malformed JSON | Connection closes with `MALFORMED_FRAME` or `MALFORMED_PAYLOAD` |
| 1.5 | Send a `game:fire` from a non-active player | Rejected with `NOT_YOUR_TURN`; state version unchanged |
| 1.6 | Send a stale `expectedStateVersion` | Rejected with `STATE_VERSION_CONFLICT` |
| 1.7 | Inspect captured traffic | No client ever receives another player's fleet layout or coordinates |

---

## 2. Physical-device matrix

| # | Configuration | Expected result |
|---|---|---|
| 2.1 | 2 Android devices | Full match completes |
| 2.2 | 2 iOS devices | Full match completes |
| 2.3 | Mixed Android/iOS | Full match completes |
| 2.4 | 6 devices | Match completes without excessive lag |
| 2.5 | Internet disabled on the router | All of the above still pass |

---

## 3. Host exit and recovery

| # | Step | Expected result |
|---|---|---|
| 3.1 | Host force-close mid-match | All clients return Home within ~10 s |
| 3.2 | Host Wi-Fi loss | All clients return Home within ~10 s |
| 3.3 | Client disconnect and reconnect | Seat restored within 30 s |
| 3.4 | Client disconnect beyond 30 s | Seat lost; client returns Home |

---

## 4. Performance and battery

| # | Step | Expected result |
|---|---|---|
| 4.1 | Run a full 6-player match | No frame drops on mid-range phones |
| 4.2 | Host a room for 30 minutes | Battery drain is acceptable; no crash |
| 4.3 | Repeated create/close cycles | No leaked sockets or listeners |

---

## 5. Release candidate checklist

- [ ] `flutter analyze` clean
- [ ] `flutter test` green
- [ ] Android release build succeeds
- [ ] iOS release build succeeds
- [ ] Store privacy disclosures mention local-network access
- [ ] No backend, cloud service or Internet dependency introduced
- [ ] `AppConfig.hostMigration == false`
- [ ] `AppConfig.hostReconnectSupported == false`
