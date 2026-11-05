# Phase 1 — Physical Device Test Procedure

> The code side of Phase 1 is complete: the room lifecycle, the admission
> rules and the lobby flows are implemented, and the lifecycle rules are
> covered by unit tests that run over real loopback TCP sockets
> (`test/host_runtime/room_lifecycle_test.dart`).
>
> The acceptance criteria of PLAN.md §15 Phase 1 need **2–6 physical devices on
> one Wi-Fi network**. This file is the checklist for that run. It has not been
> executed yet: no physical device was attached to the build machine.

---

## 0. Prerequisites

- 2–6 physical phones on the same Wi-Fi (a mix of Android and iOS is ideal).
- The app installed on each device:

```bash
cd upfleet_arena
flutter devices
flutter run -d <device-id>
```

- **The host phone must stay in the foreground.** The app warns about this,
  but a backgrounded host may be suspended by the OS and the room dies with
  it (PLAN.md §2.9).

---

## 1. Create a room

| # | Step | Expected result |
|---|---|---|
| 1.1 | Open the app → **Create Room** | The screen shows the frozen defaults: 2–6 players, 10×10, Standard fleet, 120 s / 30 s |
| 1.2 | Tap **Create room** | The app navigates to the lobby |
| 1.3 | Check the lobby | The invitation code is visible in large type, with a copy button |
| 1.4 | Check *Manual address* | It shows the host's IPv4 address and port |
| 1.5 | Check the player list | Exactly one entry, with the **Host** badge |

---

## 2. Join a room

| # | Step | Expected result |
|---|---|---|
| 2.1 | On another device: **Join Room** → **Scan** | The host room appears in the list within a few seconds |
| 2.2 | Select it, type the code, tap **Join selected room** | The client navigates to the lobby |
| 2.3 | Check the client lobby | The list shows both players; the host has the **Host** badge, the joiner does not |
| 2.4 | Check the host lobby | The host sees the new player appear |
| 2.5 | Copy the code, paste it into a chat on the phone | The code is exactly 6 characters and contains no `0`, `O`, `1` or `I` |

---

## 3. Rejections

| # | Step | Expected result |
|---|---|---|
| 3.1 | On a third device, join with a wrong code | The app shows "That invitation code is not correct." and stays on the join screen |
| 3.2 | On a third device, join with an empty nickname | The Host rejects it with the nickname message |
| 3.3 | Set the room capacity to 2 (Phase 2 adds the settings UI — for now use the default 6) and fill the room | The next join is rejected with "The room is full." |
| 3.4 | On one device, open a second join attempt while already in the room | The second connection is rejected as a duplicate of the same device |

> The protocol-version rejection cannot be triggered from the UI. It is
> covered by an automated test that sends an envelope with a mismatched
> `protocolVersion`.

---

## 4. Capacity and scale

| # | Step | Expected result |
|---|---|---|
| 4.1 | Join with 6 devices in total (host + 5) | The player counter shows `6/6` |
| 4.2 | Try a 7th device | Rejected with "The room is full." |
| 4.3 | Remove one device (leave the room) | The counter drops to `5/6` and the removed player shows as "Left the room" |
| 4.4 | Re-join from the same device | Accepted again — a player who left frees their seat |

---

## 5. Host controls

| # | Step | Expected result |
|---|---|---|
| 5.1 | On the host, tap the remove icon next to a player | A confirmation dialog appears |
| 5.2 | Confirm | The removed player sees "The host removed you from the room." and returns to the join screen; the host's list shows them as removed |
| 5.3 | On the host, tap **End room** | A confirmation dialog appears |
| 5.4 | Confirm | **Every** client returns to Home with "The host closed the room." |
| 5.5 | Check the host's phone | The room is gone; the advertisement stopped |

---

## 6. Leaving

| # | Step | Expected result |
|---|---|---|
| 6.1 | On a client, tap **Leave room** | The client returns Home; the host's list shows the player as left |
| 6.2 | On a client, use the system back gesture instead | Same result |

---

## 7. Without Internet

| # | Step | Expected result |
|---|---|---|
| 7.1 | Disable Internet on the router, keep Wi-Fi up | No change in behaviour |
| 7.2 | Repeat §2 | Discovery, the code handshake and the lobby all still work |
| 7.3 | Confirm nothing reports an "offline" mode | LAN play is expected to work without Internet |

---

## 8. Host loss

| # | Step | Expected result |
|---|---|---|
| 8.1 | With clients in the lobby, force-close the host app | Within ~10 s (3 s heartbeat, 10 s timeout) the clients report that the host is unreachable and return Home |
| 8.2 | Turn off the host's Wi-Fi instead | Same result |
| 8.3 | Confirm no client keeps playing | There is no host migration and no client-side continuation (PLAN.md §2.9) |

---

## 9. Manual fallback

| # | Step | Expected result |
|---|---|---|
| 9.1 | On the host, read the IPv4 address and the port from the lobby | Both are visible |
| 9.2 | On the client, open **Join Room** → **Manual connection** and enter them with the code | The client joins |
| 9.3 | Repeat with discovery turned off entirely | The manual path still works — it uses a direct TCP link, not mDNS |

---

## 10. Result sheet

| Scenario | Result | Notes |
|---|---|---|
| Host creates a room | | |
| A client discovers and joins | | |
| Wrong code is rejected | | |
| Full room is rejected | | |
| Duplicate device is rejected | | |
| Host removes a player | | |
| Host ends the room | | |
| Client leaves the room | | |
| 6 players in one room | | |
| Play works without Internet | | |
| Host loss is detected | | |
| Manual connection works | | |

---

## 11. After the run

1. Fill in the table and attach the notes to the Phase 1 report.
2. If the discovery backend behaved differently on Android and iOS, record it
   in `docs/adr/ADR-001-lan-discovery-and-tcp-framing.md` — the backend choice
   is still open and Phase 1 is the first real multi-device exercise of it.
3. Move to Phase 2 (Host lobby settings and synchronization) once the table
   is green.
