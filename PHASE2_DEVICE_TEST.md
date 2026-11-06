# Phase 2 — Physical Device Test Procedure

> The code side of Phase 2 is complete: the Host settings screen, the
> Host-runtime validation and the broadcast of the accepted settings are
> implemented, and they are covered by unit and widget tests
> (`test/host_runtime/room_settings_test.dart`,
> `test/features/lobby/presentation/host_settings_screen_test.dart`).
>
> The acceptance criteria of PLAN.md §15 Phase 2 need **2 physical devices on
> one Wi-Fi network**. This file is the checklist for that run. It has not been
> executed yet: no physical device was attached to the build machine.

---

## 0. Prerequisites

- 2 physical phones on the same Wi-Fi.
- The app installed on each device:

```bash
cd upfleet_arena
flutter devices
flutter run -d <device-id>
```

- **The host phone must stay in the foreground.** Closing it ends the room for
  every player (PLAN.md §2.9).

---

## 1. The Host opens the settings

| # | Step | Expected result |
|---|---|---|
| 1.1 | Host: **Create Room** → create the room | The lobby shows the invitation code and the *Room settings* card |
| 1.2 | Check the *Room settings* card | Board `10×10`, Fleet *Standard · 5 ships (4, 3, 3, 2, 2)*, capacity *up to 6 players*, timers *120 s preparation · 30 s per turn* |
| 1.3 | Tap **Edit** | The *Room settings* screen opens with the same values |
| 1.4 | Increase *Rows* to 11, *Columns* to 12 | The values change immediately, nothing is broadcast yet |
| 1.5 | Tap **Save settings** | The screen closes and the lobby card shows `11×12` |

---

## 2. The clients follow the Host

| # | Step | Expected result |
|---|---|---|
| 2.1 | On the second device: **Join Room** → scan → join with the code | The client reaches the lobby |
| 2.2 | Check the client lobby | The client sees the same `11×12` board and the same timers |
| 2.3 | Check the client lobby, *Room settings* card | It shows the values but **no** *Edit* button, plus the line "Only the host can change these settings." |
| 2.4 | Host: change the fleet to *Large* and the capacity to 4, **Save** | The client card updates to *Large · 6 ships (5, 4, 3, 3, 2, 2)* and *up to 4 players* without any action on the client |

---

## 3. Only the Host may change the settings

| # | Step | Expected result |
|---|---|---|
| 3.1 | On the client, open *Room settings* through the deep link `/lobby/settings` if reachable | Every control is disabled and the notice "Only the host can change the room settings." is shown |
| 3.2 | On the client, the *Save settings* button | Greyed out and unresponsive |
| 3.3 | Host: lower the capacity below the number of players already in the room | The stepper does not go below the seated count |

> The protocol-level rejection is covered by an automated test: a client that
> sends a handcrafted `room:config:update` is answered with
> `HOST_ONLY_ACTION`, and the room keeps its previous settings.

---

## 4. Invalid values

| # | Step | Expected result |
|---|---|---|
| 4.1 | Host: set the board to the smallest allowed size and the fleet to *Large*, **Save** | The save is accepted (19 cells fit on an 8×8 board) |
| 4.2 | Host: try to go below 8 rows or above 14 rows | The stepper stops at the limit |
| 4.3 | Host: set the preparation timer to the minimum and the turn timer to the maximum | 60 s and 60 s; the sliders stop at the limits |

---

## 5. Sharing the invitation

| # | Step | Expected result |
|---|---|---|
| 5.1 | Host: tap the copy icon next to the code | The snackbar "Invitation code copied." appears and the code is on the clipboard |
| 5.2 | Host: tap the share icon | The system share sheet opens with the code and the manual address |
| 5.3 | Share the text to another app | The code can be pasted unchanged: six characters, no `0`, `O`, `1` or `I` |

---

## 6. The settings are frozen after the lobby

| # | Step | Expected result |
|---|---|---|
| 6.1 | Host: change a setting | The change is accepted while the room is in the lobby |
| 6.2 | Host: **End room** | Every client returns Home with "The host closed the room." |
| 6.3 | Host: create a new room | The settings start again from the defaults |

---

## 7. Result sheet

| Scenario | Result | Notes |
|---|---|---|
| The Host opens and saves the settings | | |
| A client sees the same configuration | | |
| A client cannot edit the settings | | |
| The capacity cannot go below the seated count | | |
| The board, fleet and timer limits hold | | |
| The invitation code can be copied and shared | | |

---

## 8. After the run

1. Fill in the table and attach the notes to the Phase 2 report.
2. Move to Phase 3 (board renderer and ship placement) once the table is
   green.
