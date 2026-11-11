# Phase 6 — Physical Device Test Procedure

> The code side of Phase 6 is complete: the elimination and victory engine,
> the Host-computed ranking and statistics, the full `game:finished` result,
> the restricted spectator view and the Match Result screen are implemented
> and covered by unit and widget tests
> (`test/game_engine/match_result_test.dart`,
> `test/host_runtime/match_result_test.dart`,
> `test/features/match/presentation/match_result_screen_test.dart`,
> `test/features/match/presentation/match_screen_test.dart`).
>
> The acceptance criteria of PLAN.md §15 Phase 6 need **3 physical devices on
> one Wi-Fi network** (2 is the minimum, but the elimination ranking is only
> meaningful with three players). This file is the checklist for that run. It
> has not been executed yet: no physical device was attached to the build
> machine.

---

## 0. Prerequisites

- 3 physical phones on the same Wi-Fi.
- The app installed on each device:

```bash
cd upfleet_arena
flutter devices
flutter run -d <device-id>
```

- **The host phone must stay in the foreground.** Closing it ends the match
  for every player (PLAN.md §2.9).
- In *Room settings*, pick the **Small** fleet (`[3, 2, 2]`, seven cells) so a
  full match takes a few minutes instead of a quarter of an hour.
- Set the turn timer to **30 s** or more. The 15 s minimum is only needed for
  the timeout checks in section 5.

---

## 1. Elimination

| # | Step | Expected result |
|---|---|---|
| 1.1 | Sink one ship of an opponent | The attacker sees a ring and "Your shot sank a ship."; the target sees the impact on their own board |
| 1.2 | Check the *Players* tab on every device | That opponent now shows one ship fewer under "ships left" |
| 1.3 | Sink the last cell of the last ship of one player | The other players see "… sank a ship belonging to …"; the *Players* tab marks that player **Eliminated** on every device |
| 1.4 | The eliminated player's device | The first tab is now **Spectating**, not *Battle* |
| 1.5 | The following turns | The eliminated player never gets the turn again; the countdown skips straight to the next living player |
| 1.6 | The eliminated player tries to fire | There is no Fire button and no target chip; nothing can be sent |

---

## 2. The spectator view

| # | Step | Expected result |
|---|---|---|
| 2.1 | Open the *Spectating* tab | "Your fleet was sunk." and "You are watching the rest of the match. You cannot fire." |
| 2.2 | Check the turn card | It names the player who is shooting and counts the turn down, exactly like the living players see it |
| 2.3 | Check **Still in the match** | Only the living players are listed, each with their remaining ship count. The spectator is not in the list |
| 2.4 | Wait for a few shots between the survivors | **Public activity** fills from the top with lines like "Bob hit Carol." and "Carol sank a ship of Bob." |
| 2.5 | Read the activity lines carefully | No coordinate, no cell label and no ship position ever appears |
| 2.6 | Open the *Your board* tab | The spectator still sees their own sunk fleet and the impacts on it |
| 2.7 | Open the *Players* tab | The full turn order is there, with the eliminated players marked |
| 2.8 | Let more than 20 shots happen | The feed keeps only the most recent 20 and does not grow without bound |

---

## 3. Privacy while spectating

| # | Step | Expected result |
|---|---|---|
| 3.1 | Compare the spectator's *Spectating* tab with a living player's *Battle* tab | The spectator has no board of any opponent and no selectable cell |
| 3.2 | The spectator's *Your board* tab | It shows only their own fleet, never another player's |
| 3.3 | A living player's shared map | It still shows the fire of every player, each in their own colour, even after someone was eliminated |
| 3.4 | The ship counts in the roster | They match the number of ships the public activity already announced as sunk — no extra information |

> The protocol-level checks (an eliminated player firing, a spoofed player
> ID, a stale version, the exact snapshot JSON per recipient) are covered by
> `test/host_runtime/match_result_test.dart` and
> `test/host_runtime/combat_test.dart`.

---

## 4. The end of the match

| # | Step | Expected result |
|---|---|---|
| 4.1 | Sink the fleet of the second-to-last player | The match ends on **every** device at the same moment |
| 4.2 | All three devices | Each one opens the *Match result* screen automatically |
| 4.3 | The winner's phone | "You won the match." |
| 4.4 | The two defeated phones | "<winner name> won the match." |
| 4.5 | Try to fire after the end | Impossible: the battle UI is gone and the Host refuses any late command |
| 4.6 | Check the countdown | It stops; no turn timer keeps running on the result screen |

---

## 5. Timeouts

| # | Step | Expected result |
|---|---|---|
| 5.1 | Set the turn timer to 15 s and let one player idle through a turn | The turn moves on; that player is **not** eliminated |
| 5.2 | Finish the match afterwards | The result row of that player shows the right number of timeouts |
| 5.3 | Check the shot count of the same player | A skipped turn adds no shot, so `shots = hits + misses` still holds |

---

## 6. The result screen

| # | Step | Expected result |
|---|---|---|
| 6.1 | Compare the three screens side by side | The winner, the ranking order, every statistic and the duration are **identical** on all three |
| 6.2 | Check the ranking order | The winner is #1. The player whose fleet sank **last** is #2, the one who sank first is #3 |
| 6.3 | Check your own row | It is marked "(you)" and the header line reads "You finished #N" |
| 6.4 | Check the statistics of one player | `shots` equals `hits + misses`; a sinking shot is counted in `hits` **and** in `sunk` |
| 6.5 | Check the duration | "Lasted Xm Ys" matches roughly the wall-clock time from the first turn to the last shot |
| 6.6 | Count the sunk ships across all rows | The total equals the number of ships that were actually sunk during the match |
| 6.7 | A player who never fired | Their row shows 0 shots, 0 hits, 0 misses, 0 sunk |

---

## 7. Leaving the result screen

| # | Step | Expected result |
|---|---|---|
| 7.1 | A defeated player taps **Return home** | They leave the room and land on Home; the other two stay on the result screen |
| 7.2 | The host taps **End room and return home** | The room closes for everyone; all three land on Home |
| 7.3 | A client whose host closed the room first | The result screen **keeps showing the result**; the button now reads "Return home" and no longer tries to leave a closed room |
| 7.4 | The host advertising after the room ended | The room disappears from the *Join room* discovery list on the other phones |

---

## 8. Result sheet

| Scenario | Result | Notes |
|---|---|---|
| A sunk fleet eliminates its owner on every device | | |
| Eliminated players are skipped in all later turns | | |
| An eliminated player cannot fire | | |
| The spectator view is read-only and shows no coordinates | | |
| The spectator still sees their own board | | |
| The public activity feed stays bounded | | |
| The match ends exactly when one player is left alive | | |
| All devices open the result screen together | | |
| The winner is identical everywhere | | |
| The ranking is the reverse elimination order | | |
| The statistics are identical everywhere and add up | | |
| Timeouts are reported and never eliminate on their own | | |
| Return home / End room clean up correctly | | |

---

## 9. Known gaps to watch during the run

- **No local match history.** Saving the result and a history screen are the
  optional part of Phase 6 and were deliberately left out of this run. The
  result disappears when the app is closed.
- **No Play Again.** PLAN.md §2.10 keeps it post-MVP: the host creates a
  fresh room instead.
- The host's activity feed can skip its own shots while it is still alive:
  it receives private shot feedback for those instead of the public event.
  Once the host is eliminated the feed is complete. Note whether this is
  confusing during the run.
- The boards still do not zoom or pan (carried over from Phase 5, PLAN.md
  §5.3). Note the smallest phone you test on.
- Reconnect, heartbeat and Host-loss behaviour are Phase 7. If a phone drops
  off the Wi-Fi during this run, the match may stall — record it and move on.

---

## 10. After the run

1. Fill in the table and attach the notes to the Phase 6 report.
2. Move to Phase 7 (connection resilience and Host termination) once the
   table is green.