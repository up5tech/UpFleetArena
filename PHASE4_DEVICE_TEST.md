# Phase 4 — Physical Device Test Procedure

> The code side of Phase 4 is complete: the Host-owned preparation deadline,
> the countdown, the automatic fleet completion, the minimum-player rule and
> the randomized turn order are implemented and covered by unit and widget
> tests (`test/host_runtime/preparation_test.dart`,
> `test/features/match/presentation/match_screen_test.dart`).
>
> The acceptance criteria of PLAN.md §15 Phase 4 need **2 physical devices on
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
- For the timeout tests, set the preparation timer to the minimum (60 s) in
  *Room settings*.

---

## 1. Starting the preparation

| # | Step | Expected result |
|---|---|---|
| 1.1 | Host and client are both in the lobby | The host sees **Start the preparation**; the button is greyed out with only one player |
| 1.2 | Host: tap **Start the preparation** | Both devices leave the lobby and open *Prepare your fleet* |
| 1.3 | Check the countdown | A card at the top shows "The preparation ends in 2:00" and counts down on every device |
| 1.4 | Watch the countdown for 10 s | The seconds decrease smoothly; the devices may differ by a second or two |
| 1.5 | Check the note under the countdown | "A fleet that is not finished in time is placed automatically." |

---

## 2. Everyone confirms

| # | Step | Expected result |
|---|---|---|
| 2.1 | Both players place their complete fleet | Both show five ships on the board |
| 2.2 | Tap **I am ready** on the first device | The button turns into "You are ready"; the fleet can no longer be changed there |
| 2.3 | Tap **I am ready** on the second device | Both devices jump to *The match* at the same moment — the countdown does not run out |
| 2.4 | Check the turn order | Every player appears exactly once, and the first one is marked *First* |
| 2.5 | Check the header | It names the player who shoots first and the board size and fleet |

> The turn order is randomized: run the room again and the first player
> changes.

---

## 3. A confirmed fleet is locked

| # | Step | Expected result |
|---|---|---|
| 3.1 | During the preparation, confirm the fleet | The *Rotate*, *Auto* and the ship chips are greyed out |
| 3.2 | Try to tap a cell on the board anyway | Nothing moves |

---

## 4. The timeout

| # | Step | Expected result |
|---|---|---|
| 4.1 | Host: set the preparation timer to 60 s, then start the preparation | The countdown shows 1:00 |
| 4.2 | One player confirms, the other does not | The countdown keeps running |
| 4.3 | Let the countdown run out | The match starts on both devices |
| 4.4 | Check the player that did not confirm | The Host placed a complete legal fleet for them |
| 4.5 | Check the turn order | Both players are in it |

---

## 5. The minimum-player rule

| # | Step | Expected result |
|---|---|---|
| 5.1 | With only one player in the room, the host taps **Start the preparation** | The button stays greyed out and the host is told that at least two players are needed |
| 5.2 | Start the preparation with two players, then let one player leave | Both devices return to the lobby and show that not enough players are left |

---

## 6. A client clock cannot decide

| # | Step | Expected result |
|---|---|---|
| 6.1 | Start the preparation on a device whose clock is wrong by an hour | The countdown and the transition follow the host, not the client clock |
| 6.2 | Turn the system clock of the client backwards mid-countdown | The countdown is corrected by the next heartbeat and the match still starts on time |

---

## 7. Result sheet

| Scenario | Result | Notes |
|---|---|---|
| The host starts the preparation | | |
| The countdown runs on every device | | |
| The match starts when everyone is ready | | |
| The match starts when the time runs out | | |
| The missing fleet is placed automatically | | |
| A confirmed fleet cannot be changed | | |
| The turn order holds every player once | | |
| The preparation is cancelled when a player leaves | | |
| A wrong client clock changes nothing | | |

---

## 8. After the run

1. Fill in the table and attach the notes to the Phase 4 report.
2. Move to Phase 5 (turn-based combat) once the table is green.
