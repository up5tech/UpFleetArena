# Phase 5 — Physical Device Test Procedure

> The code side of Phase 5 is complete: the combat engine, the Host-side shot
> resolution with the turn deadline, the permission-filtered match views and
> the battle UI are implemented and covered by unit and widget tests
> (`test/game_engine/combat_test.dart`,
> `test/host_runtime/combat_test.dart`,
> `test/features/match/presentation/match_screen_test.dart`).
>
> The acceptance criteria of PLAN.md §15 Phase 5 need **2–3 physical devices
> on one Wi-Fi network**. This file is the checklist for that run. It has not
> been executed yet: no physical device was attached to the build machine.

---

## 0. Prerequisites

- 2–3 physical phones on the same Wi-Fi.
- The app installed on each device:

```bash
cd upfleet_arena
flutter devices
flutter run -d <device-id>
```

- **The host phone must stay in the foreground.** Closing it ends the match
  for every player (PLAN.md §2.9).
- For the timeout tests, set the turn timer to the minimum (15 s) in
  *Room settings*.

---

## 1. Entering the match

| # | Step | Expected result |
|---|---|---|
| 1.1 | Host starts the preparation, both players confirm | Both jump to *The match* at the same moment |
| 1.2 | Check the header | It names the player who shoots first and counts down the turn |
| 1.3 | Check the *Players* tab | Every player appears once, in turn order, with the current player marked |
| 1.4 | The player whose turn it is not | Sees "… is shooting" and a greyed-out Fire button |

---

## 2. Firing

| # | Step | Expected result |
|---|---|---|
| 2.1 | Active player taps a target chip | The opponent's board opens; only their own shots are marked |
| 2.2 | Tap an empty cell | The cell is highlighted and shows its coordinate (e.g. `C4`) |
| 2.3 | Tap **Fire at this cell** | The button reads "Waiting for host…" for a moment, then the result appears |
| 2.4 | A miss | A small dot on the attacker's board and "Your shot missed." |
| 2.5 | A hit | A cross on the attacker's board and "Your shot hit a ship." |
| 2.6 | The last cell of a ship | A ring on the attacker's board and "Your shot sank a ship." |
| 2.7 | The target's device | Shows the impact on their own board: "A shot hit one of your ships." |
| 2.8 | The turn | Moves to the next player automatically after one shot, hit or miss |

---

## 3. Only the active player can fire

| # | Step | Expected result |
|---|---|---|
| 3.1 | A player who is not active taps a cell and Fire | The controls are disabled; nothing is sent |
| 3.2 | Two players tap Fire at the same time | Exactly one shot is accepted; the other is refused with "It is not your turn." and the board does not change |
| 3.3 | A player fires twice in the same turn | The second shot is refused; one shot consumes exactly one turn |

---

## 4. Illegal and stale shots

| # | Step | Expected result |
|---|---|---|
| 4.1 | Fire at a cell already fired at | "You already fired at that cell." and nothing changes |
| 4.2 | Fire outside the board | Refused; the board does not change |
| 4.3 | Fire at your own board | Refused |
| 4.4 | Fire after the turn passed to someone else | Refused as a stale command |
| 4.5 | Fire after the match ended | Refused; the result stays as it was |

> The protocol-level checks (spoofed player IDs, stale versions, malformed
> payloads, concurrent fires, deadline races) are covered by
> `test/host_runtime/combat_test.dart`.

---

## 5. The turn timer

| # | Step | Expected result |
|---|---|---|
| 5.1 | Set the turn timer to 15 s and let a player do nothing | When the countdown reaches zero the turn moves to the next player on every device |
| 5.2 | Check the *Players* tab | The player who timed out shows "1 timeouts" |
| 5.3 | That player fires in a later turn | Their timeout count stays but the streak is broken |
| 5.4 | Nobody is eliminated for a single timeout | The match continues |

---

## 6. Privacy of the boards

| # | Step | Expected result |
|---|---|---|
| 6.1 | Player A fires at player B | A sees only their own shots on B's board, never B's ships |
| 6.2 | Player C, who was not involved | Sees only "A hit B" style activity — no coordinates |
| 6.3 | Player B | Sees the impact on their own fleet and their own ships |
| 6.4 | Compare the *Your board* tabs | Each device shows only its own fleet |

---

## 7. Elimination and the winner

| # | Step | Expected result |
|---|---|---|
| 7.1 | Sink every cell of one opponent's fleet | That player is marked eliminated and skipped in the following turns |
| 7.2 | The eliminated player | Cannot fire; their board stays visible to them only |
| 7.3 | Sink the last opponent | The match ends on every device with the same winner |
| 7.4 | Check the winner card | "You won the match." on the winner's phone, the winner's name on the others |
| 7.5 | Try to fire after the match ended | Refused; the result does not change |

---

## 8. Result sheet

| Scenario | Result | Notes |
|---|---|---|
| The match starts on every device at once | | |
| Only the active player can fire | | |
| One accepted shot consumes exactly one turn | | |
| Miss, hit and sunk are shown correctly | | |
| The target sees the impact on their own board | | |
| Other players see no coordinates | | |
| A repeated or illegal shot changes nothing | | |
| The turn timer skips an idle player | | |
| Timeouts are counted per player | | |
| Eliminated players are skipped | | |
| The match ends with one winner, identical everywhere | | |

---

## 9. Known gaps to watch during the run

- The boards do not zoom or pan yet. On a 14×14 board the cells are small on
  a narrow phone (PLAN.md §5.3 asks for zoom or panning). Note the smallest
  phone you test on and whether the cells are still tappable.
- The final statistics, the ranking and the spectator view are Phase 6; this
  run only checks that the match ends with the right winner.

---

## 10. After the run

1. Fill in the table and attach the notes to the Phase 5 report.
2. Move to Phase 6 (elimination, spectating and results) once the table is
   green.
