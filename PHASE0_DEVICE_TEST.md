# Phase 0 — Physical Device Test Procedure

> Phase 0 is complete on the code side: the transport, the discovery abstraction,
> the permission flow and the diagnostics screen are implemented and covered by
> unit tests. The acceptance criteria of PLAN.md §15 Phase 0 — *"two physical
> devices on the same compatible Wi-Fi can discover and connect"* — can only be
> confirmed on real hardware. This file is the checklist for that run.
>
> **No physical device was attached to the build machine while Phase 0 was
> written, so this procedure has not been executed yet.**

---

## 0. Prerequisites

- 2 physical phones on the same Wi-Fi (ideally one Android + one iOS).
- A router you can reconfigure (to disable Internet and to enable guest Wi-Fi
  or AP/client isolation).
- The app installed on both devices:

```bash
cd upfleet_arena
flutter devices                 # confirm both phones are visible
flutter run -d <device-id>      # debug build on each phone
```

- The phone that hosts must stay in the **foreground** for the whole test
  (PLAN.md §2.9).

---

## 1. Permission flow

| # | Step | Expected result |
|---|---|---|
| 1.1 | On each phone, open the app → **LAN Lab** → *Check permission* | Status shows `granted` (Android) or `implicit` (iOS) |
| 1.2 | On iOS, tap *Scan for rooms* for the first time | The system shows the local-network prompt; after allowing, discovery runs |
| 1.3 | Deny the local-network permission on one device | The app shows a readable message plus a route to system settings; it must not crash or hang |
| 1.4 | On Android 17 (API 37) build, confirm `ACCESS_LOCAL_NETWORK` appears in the *App info → Permissions* screen | The permission is declared and requestable |

Record: pass / fail + a note for each row.

---

## 2. Discovery — the backend decision

Repeat this block **once per backend** (Bonsoir and NSD) and record the result
in the table in `docs/adr/ADR-001-lan-discovery-and-tcp-framing.md`.

| # | Step | Expected result |
|---|---|---|
| 2.1 | Phone A: **Start hosting** | The card shows a port and the local IPv4 address |
| 2.2 | Phone B: **Scan for rooms** | The room appears in the list within a few seconds |
| 2.3 | Note the discovery latency | Record seconds to first appearance |
| 2.4 | Note the resolved address | Must be an IPv4 address on the same subnet as phone A |
| 2.5 | Repeat 2.1–2.4 with the other backend | Record the same values |

Decision rule: the backend that discovers reliably on **both** platforms wins.
If both qualify, prefer the one with the clearer error reporting.

---

## 3. Direct TCP connection

| # | Step | Expected result |
|---|---|---|
| 3.1 | Phone B: tap **Connect** on the discovered room | Phone B logs `Connected to …`; phone A logs `Client connected: …` |
| 3.2 | Phone A shows the client count | `Clients: 1` |
| 3.3 | Phone B: **Ping** | Both sides log a round trip; the latency is recorded under *Last round trip* |
| 3.4 | Phone B: **Split frame** | The Host answers exactly **one** pong and logs the round trip once — no duplicates, no errors |
| 3.5 | Phone B: **Oversized** | The Host logs `FRAME_TOO_LARGE` and closes the connection; phone B shows the error |
| 3.6 | Phone B: **Malformed** | The Host logs `MALFORMED_FRAME`; phone B shows the error |
| 3.7 | Phone B: **Connect manually** using phone A's IPv4 + port | Same result as 3.1–3.3 (manual fallback path) |

> Step 3.4 is the important one: it proves the receiver reassembles a message
> that arrives in three separate TCP writes.

---

## 4. Without Internet

| # | Step | Expected result |
|---|---|---|
| 4.1 | Disable Internet on the router (keep Wi-Fi up) | No behavioural change expected |
| 4.2 | Repeat 2.2 and 3.1–3.3 | Discovery and connection still work |
| 4.3 | Confirm nothing in the app reports "offline" | LAN play is expected to work without Internet (PLAN.md §5.4) |

---

## 5. Router isolation (expected failure, friendly message)

| # | Step | Expected result |
|---|---|---|
| 5.1 | Enable guest Wi-Fi or AP/client isolation | Devices are on the same SSID but cannot reach each other |
| 5.2 | Phone B scans | Either no room appears, or the connection attempt fails |
| 5.3 | Observe the UI | A readable explanation with troubleshooting steps — **never an infinite spinner** |
| 5.4 | Try the manual connection | It fails with the same readable message |

---

## 6. Mixed platform and additional scenarios

| # | Step | Expected result |
|---|---|---|
| 6.1 | Repeat §2–§3 with two Android phones | Same results |
| 6.2 | Repeat §2–§3 with two iPhones | Same results |
| 6.3 | Repeat §2–§3 with one Android + one iPhone | Same results |
| 6.4 | Background the client app, then resume it | The client reconnects or shows a clear state |
| 6.5 | Background the Host app | Document the documented limitation: the Host must stay in the foreground (PLAN.md §2.9) |
| 6.6 | Force-close the Host app | The client must detect the loss after the heartbeat timeout (3 s interval, 8–10 s timeout) and show **Host disconnected — match ended** |

---

## 7. Result sheet

| Scenario | Bonsoir | NSD | Notes |
|---|---|---|---|
| Android → Android discovery | | | |
| iOS → iOS discovery | | | |
| Android ↔ iOS discovery | | | |
| Discovery without Internet | | | |
| Discovery under AP isolation | | | |
| Direct TCP connection | | | |
| Manual IP/port fallback | | | |
| Split-frame handling | | | |
| Oversized frame rejected | | | |
| Malformed frame rejected | | | |
| Permission denial handled | | | |

**Final backend decision:** ______

---

## 8. What to do with the result

1. Record the decision in `docs/adr/ADR-001-lan-discovery-and-tcp-framing.md`
   and flip the ADR status from *provisional* to *accepted*.
2. Remove the losing package from `pubspec.yaml` and delete its implementation
   in `lib/features/lan_networking/data/`.
3. Replace the `client:ping` probe with the real `room:join` handshake
   (Phase 1).
