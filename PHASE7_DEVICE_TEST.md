# Phase 7 — Physical Device Test Procedure

> The code side of Phase 7 is complete: the Host and client heartbeats, the
> non-host reconnect token and 30-second grace period, the permission-filtered
> reconnection snapshot, the active-turn disconnect timeout behaviour, the
> explicit Host-close broadcast and the abrupt Host-loss detection are
> implemented in `lib/host_runtime/room_coordinator.dart`,
> `lib/host_runtime/host_room_service.dart`,
> `lib/features/rooms/data/room_client_session.dart` and
> `lib/features/rooms/domain/room_session_controller.dart`.
>
> The acceptance criteria of PLAN.md §15 Phase 7 need **2–3 physical devices on
> one Wi-Fi network**. This file is the checklist for that run. It has not been
> executed yet: no physical device was attached to the build machine.

---

## 0. Prerequisites

- 2–3 physical phones on the same Wi-Fi.
- The app installed on each device.
- **The host phone must stay in the foreground.** Closing it ends the match
  for every player (PLAN.md §2.9).
- Use the **Small** fleet and a **30 s** turn timer so a full match stays short.
- Note the Host's invitation code and the manual IP/port fallback before
  starting, in case discovery is blocked.

---

## 1. Ordinary client disconnect and reconnect

| # | Step | Expected result |
|---|---|---|
| 1.1 | Start a match with 2–3 players | The match runs normally |
| 1.2 | On one non-host phone, turn off Wi-Fi for 5 s, then turn it back on | The phone shows "Reconnecting to Host" while the Wi-Fi is off |
| 1.3 | Within ~30 s of the drop | The phone rejoins automatically and shows the current match state, including whose turn it is |
| 1.4 | Check the other phones | The disconnected player was marked **Disconnected** in the *Players* tab, then **Connected** again after the return |
| 1.5 | Repeat, but keep the Wi-Fi off for 40 s | The seat is no longer reclaimable; the phone returns to Home with "Host disconnected" / session expired messaging |
| 1.6 | Verify the reconnecting player's fleet | Their own ships and attack history are restored exactly as before the drop; no opponent layout is revealed |

---

## 2. Disconnect during the active turn

| # | Step | Expected result |
|---|---|---|
| 2.1 | Make sure a non-host player has the active turn | The turn countdown runs on every device |
| 2.2 | Disconnect that player (airplane mode) before they fire | Their turn timer pauses for at most the 30 s grace period |
| 2.3 | Let the grace period expire without a reconnect | The Host skips the turn, records a timeout for that player and advances to the next living player |
| 2.4 | Reconnect the player after their turn was skipped | They return as a spectator of the ongoing match and may fire on their next turn |
| 2.5 | Reconnect the player within the grace period | They may still fire before the paused deadline expires |

---

## 3. Explicit Host close

| # | Step | Expected result |
|---|---|---|
| 3.1 | Tap **End Room** / **Close Room** on the Host | Every client immediately returns to Home |
| 3.2 | Check the client message | "The host closed the room." (or the equivalent user-safe reason) |
| 3.3 | Verify the Host phone | The advertiser stops, the listener closes and the room state is cleared |
| 3.4 | Try to discover rooms again | The closed room no longer appears in the discovery list |

---

## 4. Abrupt Host loss

| # | Step | Expected result |
|---|---|---|
| 4.1 | Force-close the Host app (swipe away) during a match | Every client detects the missing heartbeat within ~10 s |
| 4.2 | Check the client message | "The connection to the host was lost. The match cannot continue without the host." |
| 4.3 | Verify no client keeps playing | No Fire button works, no turn advances, and the app returns to Home |
| 4.4 | Verify no Host election | No client offers to become the Host or to migrate the room |
| 4.5 | Disable Wi-Fi on the Host phone instead of force-closing | Same result as 4.1: heartbeat timeout, then return Home |

---

## 5. Regression checks

| # | Step | Expected result |
|---|---|---|
| 5.1 | Run the full Phase 6 flow again | Elimination, spectator view and result still work |
| 5.2 | Run a match with Internet disabled on the router | Reconnect, Host close and Host loss still behave identically |
| 5.3 | Check `AppConfig.hostMigration` and `AppConfig.hostReconnectSupported` | Both remain `false` |
| 5.4 | Inspect the network traffic | No client ever connects to another client; every frame goes Host ↔ client |

---

## 6. Known limitations carried into Phase 8

- Reconnect is best-effort within the 30 s grace period; after that the seat is
  lost and the player must join a new room.
- The Host must remain in the foreground; backgrounding may pause timers and
  trigger a Host-loss on the clients.
- No automatic reconnection UI beyond the connection-lost message is provided
  yet; Phase 8 adds the polished permission and troubleshooting flows.
- Host-side cheating and packet inspection are still out of scope
  (PLAN.md §12).
