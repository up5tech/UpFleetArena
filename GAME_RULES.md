# UpFleet Arena — Game Rules

> **Status:** Frozen for the MVP. These rules are the agreed baseline for implementation.
> **Source:** PLAN.md §2 (Game Rules), §18 (Recommended Initial Configuration), §19 (Decisions Already Confirmed).
>
> Changing any rule in this document requires an explicit product decision and a
> matching update to `AppConfig` in `upfleet_arena/lib/core/config/app_config.dart`.
> The Host runtime re-validates every value it receives from a client; the values
> here are defaults, never client-trusted constants.

---

## 1. Match format

| Aspect | Value |
|---|---|
| Mode | Private-room, free-for-all naval combat (Battleship-style) |
| Players | 2 minimum, 6 recommended, structures kept flexible up to 8 |
| Minimum to start | 2 connected eligible players, Host included |
| Network | Same Wi-Fi / LAN only |
| Internet | Not required for discovery, joining, gameplay, timers or results |
| Backend | None. The Host phone runs the whole authority in-process |
| Accounts | None. A local guest profile (nickname + avatar) only |
| Spectators | Eliminated players stay connected read-only. No new joiners after placement starts |

The Host is a normal participant — they place ships, take turns, can be
eliminated and can win — and additionally owns room configuration, validation
and timers.

### 1.1 Room invitation code

- 6 characters, generated locally with a cryptographically secure random source.
- Alphabet excludes the visually ambiguous `0`, `O`, `1` and `I`.
- Unique among active rooms on the Host.
- The code is **never** part of mDNS/Bonjour discovery metadata. Every device on
  the LAN can inspect discovery announcements; the code travels only inside the
  TCP handshake.

---

## 2. Battlefield model

Each player owns **one private board**. There is no shared map in the MVP.

- Every player places their own fleet on their own grid.
- On a turn, the active player selects a living opponent, then a coordinate on
  that opponent's grid.
- The target player sees the impact on their own board.
- The attacker sees the result of their own shot and records it in their
  attack history for that target.
- Other players receive a limited public activity event only — never ship
  positions or exact coordinates.
- The Host stores every complete fleet layout because it must validate shots.
  A curious or malicious Host can therefore inspect hidden fleet data. This is
  a documented trust limitation of a no-backend, participant-hosted design.

---

## 3. Board dimensions

| Setting | Default | MVP range |
|---|---:|---:|
| Columns | 10 | 8–14 |
| Rows | 10 | 8–14 |
| Board shape | Square | Square or rectangle |
| Cell shape | Square | Fixed square cells; board may scroll or scale |

`rows` and `columns` are stored independently. The engine must validate
rectangular boards even if the first UI only offers square presets.

---

## 4. Fleet configuration

The Host picks a fleet preset. A raw ship count is not enough, because
placement validation and sinking depend on each ship's length.

| Preset | Ship lengths | Ship count |
|---|---|---:|
| Small Fleet | `[3, 2, 2]` | 3 |
| Standard Fleet | `[4, 3, 3, 2, 2]` | 5 |
| Large Fleet | `[5, 4, 3, 3, 2, 2]` | 6 |

Rules:

- Ships are straight and occupy consecutive cells, horizontally or vertically.
- Ships may not overlap.
- Ships **may** touch each other in the MVP; edge and diagonal adjacency are
  allowed.
- Every ship must be fully inside the board.
- The fleet profile must pass a fit check against the selected board size.
- Custom fleet editing comes after the preset-based MVP is stable.

---

## 5. Placement phase

- The Host chooses the preparation duration. Range 60–180 s, default 120 s.
- The Host is the only authority for the deadline. Client countdowns are
  visual estimates only.
- Every player places all ships on their own board and can rotate ships.
- Manual placement and **Auto Place** are both provided.
- **Ready** is enabled only when the whole fleet is placed legally.
- A ready player may not change their fleet unless the Host resets the
  placement phase.
- The match starts immediately when every connected eligible player is ready.
- When the timer expires, the Host auto-places incomplete fleets with a
  validated random algorithm and marks those players ready. This rule must be
  communicated in the lobby and in the placement UI.
- If fewer than two eligible players remain when the timer expires, the match
  is cancelled and the room returns to the lobby.

---

## 6. Turn order and firing

- The Host randomly selects the first player after placement completes and
  randomizes the remaining order.
- Turns proceed in a circular order.
- One shot per turn, whether the shot hits or misses. A hit grants no extra
  shot in the MVP.
- The active player may target any living opponent except themselves.
- A cell may be fired at only once per attacker-target pair. The Host
  validates this.
- The Host resolves a shot to exactly one of `MISS`, `HIT` or `SHIP_SUNK`.
- A player is eliminated when every cell of every ship in their fleet has
  been hit.
- When one player remains alive, that player wins and the match ends.

---

## 7. Turn deadline

- Default 30 s. Host-configurable range 15–60 s.
- The Host starts and owns every turn deadline. Clients render a countdown
  from the most recently received remaining-duration information.
- A player who does not fire before the deadline is skipped; the turn advances
  to the next living player.
- Consecutive timeouts are counted and displayed. A player is **not**
  eliminated for a single timeout in the MVP.
- A host rule may forfeit a repeatedly timing-out player. This stays out of
  the initial game loop unless testing shows it is needed.

---

## 8. Non-host disconnect policy

- The Host stays the authority as long as its app runs and is reachable.
- A temporarily disconnected player keeps their fleet and match state in Host
  memory.
- The player may reconnect and reclaim their seat with a short-lived,
  randomly generated **resume token** stored locally on their device.
- Recommended reconnect grace period: 30 s.
- If the disconnected player owns the active turn, the Host may pause that
  turn's timer for at most the grace period; otherwise the turn is skipped and
  the player marked disconnected.
- A player who reconnects within the grace period receives a fresh,
  permission-filtered state snapshot.
- A client must never declare another player eliminated.
- There is no cloud state. If the Host app terminates, no client can recover
  the active match.

---

## 9. Host exit and Host loss

**There is no host migration. A Host exit terminates the room and the match.**

- On **Exit Room**, **Close Room** or **End Match**, the Host first broadcasts
  `room:closed` or `game:aborted` with a user-safe reason, then closes every
  client socket, stops LAN service advertising and closes the TCP listener.
- If the Host app is force-closed, crashes or loses Wi-Fi before broadcasting,
  clients detect the missing Host heartbeat and show **Host disconnected —
  match ended**.
- Heartbeat interval ≈ 3 s; unreachable timeout ≈ 8–10 s. The timeout detects
  an abrupt failure only — it is not a Host reconnect grace period.
- Once the Host is unavailable, every client marks the match
  `ABORTED_HOST_LOST`, returns to Home and clears its active-room state. A
  client must never elect a new Host or continue the game on its own.
- The Host must stay in the foreground while hosting; mobile operating systems
  can suspend background work. The app warns before leaving the foreground and
  keeps the screen awake where appropriate.

---

## 10. Match end

The Host computes and broadcasts the final result:

- Winner player ID and display name.
- Final ranking / elimination order.
- Match duration.
- Per-player statistics: shots, hits, misses, ships sunk, timeouts.
- A locally generated match ID and the final state version.

Each device may save its own copy of the result to local history. There is no
central match-history service. **Play Again** is a post-MVP enhancement; in the
MVP everyone returns Home, or the Host creates a fresh room with the previous
configuration prefilled.

---

## 11. Open questions deferred to later phases

These are deliberately *not* decided here. Each is resolved in the phase named
in brackets, and the decision is recorded back into this document.

| Question | Phase |
|---|---|
| Host-configurable board presets beyond square | 2 |
| Language set and localization scope | 8 |
| Custom fleet editor | Post-MVP |
| AI practice mode | Post-MVP |
| Exact forfeit rule for repeated turn timeouts | 5+ |
