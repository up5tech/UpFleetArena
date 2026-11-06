# Phase 3 — Physical Device Test Procedure

> The code side of Phase 3 is complete: the board renderer, the placement
> interaction, the pure placement engine and the Host-side placement runtime
> are implemented and covered by unit and widget tests
> (`test/game_engine/placement_test.dart`,
> `test/host_runtime/placement_test.dart`,
> `test/features/placement/presentation/placement_screen_test.dart`).
>
> The acceptance criteria of PLAN.md §15 Phase 3 need **2 physical devices on
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

## 1. The board

| # | Step | Expected result |
|---|---|---|
| 1.1 | In the lobby, tap **Prepare your fleet** | The *Prepare your fleet* screen opens with a `10×10` grid |
| 1.2 | Check the *Your fleet* row | Five chips, one per ship of the Standard preset: `4 cells`, `3 cells`, `3 cells`, `2 cells`, `2 cells` |
| 1.3 | Tap a chip | The chip is highlighted and the *Rotate* button becomes active |
| 1.4 | Drag a finger across the board | A ghost of the ship follows the finger; it is green when it fits and red when it does not |
| 1.5 | Release the finger outside the board | No ship is placed |

---

## 2. Placing a ship

| # | Step | Expected result |
|---|---|---|
| 2.1 | Select the `4 cells` chip and tap an empty cell | The ship appears on the board, anchored at the tapped cell |
| 2.2 | The chip of that ship | Now shows a check mark |
| 2.3 | Tap the same cell again | Nothing changes — the ship stays where it is |
| 2.4 | Select the `3 cells` chip and tap a cell that overlaps the first ship | The ship is not placed and a red hint says "That ship overlaps another one." |
| 2.5 | Select the `3 cells` chip and tap a cell at the right edge of the board | The ship is not placed and the hint says "That ship does not fit on the board." |
| 2.6 | Move the finger over a valid cell and release | The ship is placed there |

---

## 3. Rotating, moving and undo

| # | Step | Expected result |
|---|---|---|
| 3.1 | Select a placed ship and tap **Rotate** | The ship turns around its anchor cell; a horizontal ship becomes vertical |
| 3.2 | Rotate a ship so that it would leave the board | The rotation is refused and the hint explains it |
| 3.3 | Select a placed ship and tap another cell | The ship moves to the new cell |
| 3.4 | Tap **Undo** | The last change is reverted |
| 3.5 | Tap **Undo** repeatedly | The changes are undone one by one, down to the first layout |
| 3.6 | Tap **Undo** when nothing was changed | The button is greyed out |

---

## 4. Auto place

| # | Step | Expected result |
|---|---|---|
| 4.1 | Tap **Auto** | The Host places the whole fleet; all five ships appear on the board |
| 4.2 | Check the chips | Every chip shows a check mark |
| 4.3 | Tap **Undo** | The manual layout from before the automatic placement comes back |

---

## 5. Ready

| # | Step | Expected result |
|---|---|---|
| 5.1 | With only some ships placed, look at the button at the bottom | It reads "Place every ship first" and is greyed out |
| 5.2 | Place every ship | The button reads "I am ready" and is active |
| 5.3 | Tap **I am ready** | The button reads "You are ready" and the *Players* card shows the player as *Ready* |
| 5.4 | On the other device, look at the *Players* card | It shows the first player as *Ready* and the second one as *Placing* |
| 5.5 | Change a ship after being ready | The confirmation is cleared and the player shows as *Placing* again |

---

## 6. The layout stays private

| # | Step | Expected result |
|---|---|---|
| 6.1 | On the host, place a fleet and note the position of a ship | The Host knows every ship of every player |
| 6.2 | On the second device, do **not** open the placement screen | The lobby shows only the names and the readiness, never a board of another player |
| 6.3 | Compare the two devices | The second device cannot see the first device's ships at all — the lobby has no board for other players |

> The protocol-level privacy is covered by an automated test: the layout of a
> player is never sent to another connection, and the public readiness event
> carries no coordinates.

---

## 7. The settings still reset the fleets

| # | Step | Expected result |
|---|---|---|
| 7.1 | Both players place a fleet | Both boards are complete |
| 7.2 | Host: change the board size to `12×12` and **Save** | The placements are cleared on both devices |
| 7.3 | Host: change the fleet preset to *Large* and **Save** | The fleet now asks for six ships; the old layout is cleared again |

---

## 8. Result sheet

| Scenario | Result | Notes |
|---|---|---|
| The board renders and the fleet shows the preset | | |
| A ship is placed with a tap and with a drag | | |
| An overlapping ship is refused | | |
| A ship outside the board is refused | | |
| Rotate, move and undo work | | |
| Auto place fills the whole fleet | | |
| Ready is only possible with a complete fleet | | |
| The readiness of the other players is visible | | |
| Another player's layout is not visible | | |
| A new board size clears the layouts | | |

---

## 9. After the run

1. Fill in the table and attach the notes to the Phase 3 report.
2. Move to Phase 4 (preparation timer and match start) once the table is
   green.
