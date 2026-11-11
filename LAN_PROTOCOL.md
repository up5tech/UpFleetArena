# UpFleet Arena — LAN Protocol

> **Status:** Phase 0 transport specification. Frozen for the MVP.
> **Source:** PLAN.md §6 (Technical Architecture), §7 (Data Model), §8 (LAN Message Protocol).
>
> This document describes the wire format and the message catalogue. The
> implementation of the framing layer lives in
> `upfleet_arena/lib/features/lan_networking/services/frame_codec.dart` and the
> envelope in `upfleet_arena/lib/shared/protocol/protocol_message.dart`.

---

## 1. Topology

Star topology. The Host phone runs an in-process TCP server; every client opens
**one** long-lived TCP connection to the Host. Clients never connect to each
other.

```text
                      ┌──────────────────────────┐
                      │ Host phone               │
                      │  RoomCoordinator         │
                      │  GameEngine              │
                      │  MatchStateStore         │
                      │  HostTimerController     │
                      │  ServerSocket (TCP)      │
                      │  mDNS / Bonjour advert.   │
                      └────────────┬─────────────┘
                                   │  Local Wi-Fi / LAN
              ┌────────────────────┼────────────────────┐
        ┌─────▼─────┐        ┌─────▼─────┐        ┌─────▼─────┐
        │ Client 2  │        │ Client 3  │        │ Client N  │
        │  Socket   │        │  Socket   │        │  Socket   │
        └───────────┘        └───────────┘        └───────────┘
```

The Host is a trusted authority, not a cheat-proof server: it owns the complete
game state on a participant's device. The MVP targets friendly local play.

---

## 2. Framing

Each TCP message is a **length-prefixed JSON frame**.

```text
+---------------------------+-----------------------------+
| uint32 big-endian length  | UTF-8 JSON payload          |
| 4 bytes                   | `length` bytes              |
+---------------------------+-----------------------------+
```

Rules:

- The length prefix counts **payload bytes only**, not the header.
- The payload is a single JSON **object** (not an array, not a bare value).
- Maximum accepted inbound payload: **64 KiB** (65 536 bytes).
- A frame declaring a larger length is rejected with `FRAME_TOO_LARGE`.
- A payload that is not valid UTF-8, not valid JSON, or not a JSON object is
  rejected with `MALFORMED_PAYLOAD` / `MALFORMED_FRAME`.

### 2.1 Stream semantics

TCP is a byte stream: one read is **not** one message, and one message may span
many reads. The receiver therefore keeps a buffer and emits a message only when
the declared length has been fully received.

Required receiver behaviour:

| Input | Expected output |
|---|---|
| A frame split across N reads | Exactly one message, after the last byte |
| Two frames delivered in one read | Exactly two messages, in order |
| A split that lands inside the length prefix | Exactly one message, after the remainder arrives |
| A declared length above 64 KiB | Reject with `FRAME_TOO_LARGE`, close the connection |
| A malformed payload | Reject with `MALFORMED_FRAME` / `MALFORMED_PAYLOAD` |

These cases are covered by unit tests in
`upfleet_arena/test/features/lan_networking/services/frame_codec_test.dart` and
can be reproduced on-device from the LAN Lab **Transport diagnostics** panel
(*Split frame*, *Oversized*, *Malformed* buttons).

---

## 3. Envelope

Every frame uses the same envelope so the Host can route it, correlate the
acknowledgement, and detect a stale state version.

```json
{
  "protocolVersion": 2,
  "messageType": "game:fire",
  "requestId": "local-uuid",
  "roomId": "room-uuid",
  "playerId": "player-uuid",
  "expectedStateVersion": 24,
  "payload": {
    "row": 3,
    "column": 7
  }
}
```

| Field | Required | Meaning |
|---|---|---|
| `protocolVersion` | yes | Integer protocol version. Currently `2`. |
| `messageType` | yes | Route key, e.g. `room:join`. |
| `requestId` | recommended | Correlation id echoed in the acknowledgement. |
| `roomId` | session-dependent | Room the message belongs to. |
| `playerId` | session-dependent | Sender claim. **The Host resolves the real identity from the accepted socket and does not trust this field.** |
| `expectedStateVersion` | state-dependent | Version the sender believed was current. |
| `payload` | yes | JSON object body. May be empty. |

Unknown protocol versions are rejected with `UNSUPPORTED_PROTOCOL_VERSION`.
Unknown critical message types are rejected safely.

---

## 4. Discovery

- Service type: `_upfleet._tcp`.
- The Host advertises a **non-secret** room label or Host nickname.
- The invitation code is **never** part of the service name, the service type
  or any TXT attribute — every device on the LAN can inspect announcements.
- TXT attributes currently carry only `v` (protocol version) and `app`
  (`upfleet`).
- The client resolves the service, then connects to the **resolved IP address
  and port**. `.local` hostname resolution is not assumed to work on every OS.
- IPv4 is the first-tested path; IPv6 service addresses must be handled
  correctly if the plugin returns them.

The discovery backend is still under evaluation — see
`docs/adr/ADR-001-lan-discovery-and-tcp-framing.md`.

---

## 5. Client → Host commands

| Message | Purpose | Host-side validation |
|---|---|---|
| `room:join` | Join by invitation code | Correct code, supported protocol, room joinable, capacity available |
| `room:leave` | Leave room | Sender is a room member; apply the leave policy |
| `room:config:update` | Update room settings | Sender is Host; lobby still configurable; config passes limits |
| `room:player:kick` | Remove a lobby player | Sender is Host; target is a member; match not started |
| `room:start-placement` | Start the preparation phase | Sender is Host; minimum player count; valid config |
| `room:close` | Close room / end match | Sender is Host |
| `placement:set` | Set the fleet layout | Sender owns the board; the room still accepts placements; layout valid |
| `placement:auto` | Request automatic placement | Sender owns the board; the room still accepts placements |
| `placement:ready` | Confirm a complete fleet | All ships placed legally |
| `game:fire` | Fire at a coordinate of the shared map | Authenticated sender owns the live turn; the command names the current match, turn and state version; valid cell; no repeated shot by this attacker |
| `game:request-snapshot` | Request the current authorized state | Sender is still admitted to the room/match |
| `client:heartbeat` | Report connection health | Valid active connection |
| `session:resume` | Reclaim a temporarily disconnected seat | Resume token valid; Host room still active; grace period not expired |

Phase 0 additionally defines `client:ping` as a transport probe, answered with
`host:pong` echoing the `nonce` and the `requestId`.

---

## 6. Host → client events

| Event | Purpose |
|---|---|
| `room:joined` | Player ID, room ID, filtered lobby snapshot, resume token |
| `room:state` | Player list, settings, readiness, phase |
| `room:player-joined` | New member joined |
| `room:player-left` | Member left or was removed |
| `room:config-updated` | New Host settings |
| `room:closed` | Host explicitly closed the room or ended the match. Also sent to a single client that was removed from the room, with `reason: "kicked"` |
| `placement:started` | Placement deadline and fleet profile |
| `placement:cancelled` | The preparation was cancelled; the room returns to the lobby |
| `placement:state` | The exact fleet layout, sent to its owner only |
| `placement:ready-state` | Public readiness projection |
| `placement:completed` | Placement phase ended; match is starting |
| `game:started` | Turn order and initial public match state |
| `game:turn-started` | Active player and turn deadline / remaining time |
| `game:shot-result` | Caller-authorized shot result |
| `game:public-activity` | Limited event for other players |
| `game:player-eliminated` | Public elimination event |
| `game:player-disconnected` | Non-host connection status update |
| `game:player-reconnected` | Non-host reconnection status update |
| `game:state-snapshot` | Permission-filtered current state |
| `game:finished` | Winner, ranking, final statistics and the revealed fleets |
| `game:aborted` | Host loss or explicit early termination |
| `host:heartbeat` | Host liveness signal and current state version |
| `protocol:error` | Stable error code and safe user-facing message |

Phase 0 additionally defines `host:pong` as the reply to `client:ping`.

---

## 7. Error codes

Stable machine-readable codes. Never reword an existing code; add a new one
instead.

| Code | Meaning |
|---|---|
| `ROOM_NOT_FOUND` | No room with that code on this Host |
| `ROOM_CODE_INVALID` | The invitation code does not match |
| `ROOM_FULL` | The room reached its player capacity |
| `ROOM_ALREADY_STARTED` | The room left the joinable phase |
| `HOST_ONLY_ACTION` | A non-Host tried a Host-only command |
| `INVALID_ROOM_CONFIG` | The settings failed Host-side validation |
| `UNSUPPORTED_PROTOCOL_VERSION` | The client's `protocolVersion` is not supported |
| `PLACEMENT_PHASE_NOT_ACTIVE` | Placement command outside the placement phase |
| `INVALID_SHIP_PLACEMENT` | Out of bounds or overlapping placement |
| `FLEET_INCOMPLETE` | Ready pressed with ships still unplaced |
| `NOT_YOUR_TURN` | The sender does not own the active turn |
| `TARGET_NOT_ALIVE` | The target is eliminated or invalid |
| `INVALID_TARGET_CELL` | Row/column outside the board |
| `CELL_ALREADY_FIRED_AT` | The attacker already fired at that target cell |
| `MATCH_ALREADY_FINISHED` | The match is over |
| `STATE_VERSION_CONFLICT` | `expectedStateVersion` is stale |
| `SESSION_EXPIRED` | Resume token invalid or grace period elapsed |
| `HOST_CLOSING_ROOM` | The room is shutting down; no new commands accepted |
| `LAN_PERMISSION_DENIED` | Local-network access is not granted |
| `HOST_UNREACHABLE` | The Host did not answer |
| `RATE_LIMITED` | Too many requests from this connection |
| `FRAME_TOO_LARGE` | Declared frame length exceeds 64 KiB |
| `MALFORMED_FRAME` | The payload is not valid JSON |
| `MALFORMED_PAYLOAD` | The payload is not a JSON object, or is not valid UTF-8 |

Room-lifecycle codes added in Phase 1. Existing codes are never reworded; a
new situation gets a new code.

| Code | Meaning |
|---|---|
| `DEVICE_ALREADY_CONNECTED` | This device already has an active seat in the room |
| `INVALID_DISPLAY_NAME` | The nickname is empty, too long, or a reserved system label |
| `UNKNOWN_MESSAGE_TYPE` | The command is not part of the protocol |
| `ALREADY_JOINED` | The connection already completed the join handshake |
| `PLAYER_NOT_FOUND` | The targeted player is no longer in the room |
| `NOT_ROOM_MEMBER` | The sender is not a member of the room |

Preparation-phase codes added in Phase 4.

| Code | Meaning |
|---|---|
| `NOT_ENOUGH_PLAYERS` | Fewer than two connected players are needed to start the preparation |
| `PLACEMENT_LOCKED` | The fleet is confirmed and can no longer be changed |

A `protocol:error` never carries stack traces, local file paths, raw exception
text or private fleet data.

---

## 8. Information visibility

- Never send another player's complete fleet layout to an opponent.
- During placement, a player receives their own exact fleet layout and other
  players' readiness only.
- During a match, the target receives impact coordinates for shots against
  their own board; the attacker receives the result of their own shot.
- The battle map is shared: every player sees the shots that were fired at an
  opponent, each marked with the shooter who fired it. A shared map reveals
  **where the shots landed**, so a hit becomes common knowledge of the room.
  The **layout** of a fleet still stays with the Host and its owner.
- Other players receive public match events and aggregate status only.
- Eliminated players receive a restricted spectator projection: their own
  sunk fleet, the public roster with aggregate fleet status and the public
  activity events. They get no fire affordance and the Host refuses any shot
  they send.
- The final ranking and the per-player statistics are computed by the Host
  and broadcast identically to every client.
- Client clocks, turn counters, hit calculations, ship counts and match status
  are never trusted. The Host owns all of them.
- Host-side complete state stays separate from serialized client view models.
- Resume tokens and full fleet layouts are never logged.

---

## 8.1 The join handshake

The client opens the TCP connection and sends one `room:join` command:

```json
{
  "protocolVersion": 1,
  "messageType": "room:join",
  "requestId": "local-uuid",
  "payload": {
    "code": "ABC234",
    "displayName": "Alice",
    "avatarId": "🐙",
    "deviceId": "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
  }
}
```

| Field | Required | Meaning |
|---|---|---|
| `code` | yes | The six-character invitation code, compared case-insensitively |
| `displayName` | yes | The player's nickname. Validated by the Host |
| `avatarId` | no | The chosen avatar identifier |
| `deviceId` | yes | A locally generated, per-device identifier. Used to reject a second concurrent connection from the same device |

The Host validates the command in this order and answers with the first
failure:

1. protocol version → `UNSUPPORTED_PROTOCOL_VERSION`
2. the room exists → `ROOM_NOT_FOUND`
3. the code matches → `ROOM_CODE_INVALID`
4. the room is still joinable → `ROOM_ALREADY_STARTED`
5. the nickname is acceptable → `INVALID_DISPLAY_NAME`
6. the device has no active seat → `DEVICE_ALREADY_CONNECTED`
7. the room has a free seat → `ROOM_FULL`

On success the Host answers with `room:joined`:

```json
{
  "messageType": "room:joined",
  "requestId": "local-uuid",
  "payload": {
    "playerId": "player-uuid",
    "roomId": "room-uuid",
    "resumeToken": "random-token",
    "snapshot": { }
  }
}
```

- `playerId` is generated by the Host. The client may not choose it.
- `resumeToken` is shown exactly once. The Host stores only its SHA-256
  hash; the raw token is never logged and never sent again.
- `snapshot` is the room projection for this viewer (§8.2).

Every rejection is answered with `protocol:error` carrying the code and a
user-safe message.

## 8.2 Room projections

The Host never broadcasts one serialized internal state. It builds a
projection per recipient through `ProjectionBuilder`:

| Field | Visibility |
|---|---|
| `roomId`, `status`, `stateVersion` | everybody |
| `config` | everybody (the settings are public room information) |
| `players[]` | identity and connection status only: `playerId`, `displayName`, `avatarId`, `role`, `status`, `ready` |
| `viewerPlayerId` | the recipient only |
| `viewerIsHost` | the recipient only |

The Host badge comes from the Host, never from the client's own bookkeeping.

## 8.3 Room settings

Only the Host changes the room settings. The Host device applies them
locally; a `room:config:update` command is accepted only from a session
bound to the Host player ID.

```json
{
  "messageType": "room:config:update",
  "requestId": "local-uuid",
  "payload": {
    "config": {
      "rows": 10,
      "columns": 10,
      "fleetPreset": "STANDARD",
      "maxPlayers": 6,
      "placementDurationSeconds": 120,
      "turnDurationSeconds": 30
    }
  }
}
```

| Field | Limits |
|---|---|
| `rows` | 8–14 |
| `columns` | 8–14 |
| `fleetPreset` | `SMALL` `[3,2,2]`, `STANDARD` `[4,3,3,2,2]`, `LARGE` `[5,4,3,3,2,2]` |
| `maxPlayers` | 2–6 and never below the number of seated players |
| `placementDurationSeconds` | 60–180 |
| `turnDurationSeconds` | 15–60 |

The Host validates the command in this order and answers with the first
failure:

1. the sender is the Host → `HOST_ONLY_ACTION`
2. the room is still in the lobby → `ROOM_ALREADY_STARTED`
3. the payload is well formed → `INVALID_ROOM_CONFIG`
4. every value is inside its limits → `INVALID_ROOM_CONFIG`

An accepted change is broadcast to every admitted client as
`room:config-updated`:

```json
{
  "messageType": "room:config-updated",
  "payload": {
    "config": { },
    "stateVersion": 7,
    "snapshot": { }
  }
}
```

- `config` is the accepted configuration.
- `stateVersion` is the room state version after the change. It increases by
  exactly one per accepted change.
- `snapshot` is the per-recipient room projection (§8.2).

A client never sends `room:config:update`: its own copy of the settings is
read-only and only the Host sees the editing controls.

## 8.4 Fleet placement

Every player prepares their own fleet. The Host owns the exact layout and
sends it back to its owner only — no other client ever receives the
coordinates of a ship (PLAN.md §8).

Until Phase 4 starts the preparation phase, the fleet is prepared while the
room is still in the lobby. The commands below are therefore accepted while
the room is in the lobby and rejected with `PLACEMENT_PHASE_NOT_ACTIVE` once
the room left it.

### `placement:set`

```json
{
  "messageType": "placement:set",
  "requestId": "local-uuid",
  "payload": {
    "ships": [
      {
        "shipId": "ship-1",
        "length": 4,
        "orientation": "horizontal",
        "row": 0,
        "column": 0
      }
    ]
  }
}
```

| Field | Meaning |
|---|---|
| `shipId` | The identifier of the ship, e.g. `ship-1`. Derived from the fleet preset |
| `length` | The length of the ship in cells. It must match the preset |
| `orientation` | `horizontal` or `vertical` |
| `row`, `column` | The anchor cell of the ship: the leftmost cell of a horizontal ship, the topmost cell of a vertical one |

The command carries the complete layout of the sender. The Host validates
every ship of it and either accepts the whole layout or rejects the whole
command:

1. the sender is a room member → `NOT_ROOM_MEMBER`
2. the room still accepts placements → `PLACEMENT_PHASE_NOT_ACTIVE`
3. the payload is well formed → `INVALID_SHIP_PLACEMENT`
4. every ship belongs to the fleet preset → `INVALID_SHIP_PLACEMENT`
5. every ship is inside the board → `INVALID_SHIP_PLACEMENT`
6. no two ships overlap → `INVALID_SHIP_PLACEMENT`

Ships may touch each other; only an overlap is rejected. A layout may be
incomplete — the player places the ships one by one.

### `placement:auto`

Asks the Host to place the whole fleet with the automatic algorithm. The
Host owns the random source and answers with the resulting layout.

### `placement:ready`

Confirms the fleet. The Host checks that every ship of the preset is placed
and legal, then marks the player as ready. An incomplete fleet is rejected
with `FLEET_INCOMPLETE`.

Changing the fleet clears the confirmation, so a player never stays ready
with a layout the Host did not accept.

### `placement:state`

The answer to every placement command, sent to the owner of the fleet only:

```json
{
  "messageType": "placement:state",
  "payload": {
    "playerId": "player-uuid",
    "ships": [ ],
    "ready": false,
    "stateVersion": 12
  }
}
```

### `placement:ready-state`

The readiness of every member, sent to everybody. It carries no
coordinates:

```json
{
  "messageType": "placement:ready-state",
  "payload": {
    "players": [
      { "playerId": "player-uuid", "displayName": "Alice", "ready": true }
    ],
    "stateVersion": 12
  }
}
```

A new board size or a new fleet preset invalidates every stored layout: the
Host clears the layouts and the confirmations.

## 8.5 The preparation phase

The Host owns the preparation deadline. A client never computes it and never
sends a remaining time (PLAN.md §9.4).

### `room:start-placement`

The Host moves the room from the lobby into the preparation phase. The Host
validates the command in this order:

1. the sender is the Host → `HOST_ONLY_ACTION`
2. the room is still in the lobby → `ROOM_ALREADY_STARTED`
3. at least two players are connected and the settings are valid →
   `NOT_ENOUGH_PLAYERS`

The Host then sets the deadline to now plus the configured preparation
duration and answers with `placement:started`:

```json
{
  "messageType": "placement:started",
  "payload": {
    "remainingSeconds": 120,
    "durationSeconds": 120,
    "fleetPreset": "STANDARD",
    "boardRows": 10,
    "boardColumns": 10,
    "stateVersion": 14
  }
}
```

### The countdown

The `host:heartbeat` event carries the seconds that are left:

```json
{
  "messageType": "host:heartbeat",
  "payload": {
    "stateVersion": 17,
    "placementRemainingSeconds": 42
  }
}
```

The field is missing while no preparation is running. A client counts down
locally from the last value it received and corrects itself with every
heartbeat; the countdown is display-only.

### The end of the preparation

The preparation ends in one of three ways, and only the Host decides which one
it is:

| Trigger | Result |
|---|---|
| Every connected player confirmed a fleet | The match starts at once |
| The deadline passes | The Host completes the missing fleets and starts the match |
| Fewer than two players are left | The preparation is cancelled and the room returns to the lobby |

The automatic completion uses the same engine as the *Auto Place* button, so
it always produces a legal fleet. If it cannot, the preparation is cancelled
with a controlled error instead of starting a broken match.

A confirmed fleet is locked: it can no longer be changed during the
preparation. The command is rejected with `PLACEMENT_LOCKED`.

### `game:started`

The match starts with a randomized turn order:

```json
{
  "messageType": "game:started",
  "payload": {
    "matchId": "match-uuid",
    "turnOrder": [
      { "playerId": "player-uuid", "displayName": "Alice" }
    ],
    "activePlayerId": "player-uuid",
    "boardRows": 10,
    "boardColumns": 10,
    "fleetPreset": "STANDARD",
    "stateVersion": 21
  }
}
```

The first player of the order takes the first turn. The turn order holds
every player of the room exactly once.

### `placement:cancelled`

The preparation was cancelled and the room returned to the lobby:

```json
{
  "messageType": "placement:cancelled",
  "payload": {
    "reason": "Not enough players are left to start the match.",
    "stateVersion": 18
  }
}
```

## 8.6 Combat

### `game:fire`

```json
{
  "messageType": "game:fire",
  "requestId": "fire-17",
  "roomId": "room-uuid",
  "expectedStateVersion": 14,
  "payload": {
    "matchId": "match-uuid",
    "turnNumber": 5,
    "row": 3,
    "column": 7
  }
}
```

| Field | Meaning |
|---|---|
| `requestId` | Required. Echoed back in the `game:shot-result` acknowledgement so the sender can match the answer to its own request |
| `expectedStateVersion` | Required. The version the sender believed was current |
| `matchId`, `turnNumber` | The match and turn the shot was aimed at |
| `row`, `column` | Zero-based cell on the single shared battle map |

The command names **no target**. One shot is resolved against every living
opponent at the same cell, on the one battle map the whole room shares.

The Host resolves the sender from the accepted socket and never trusts a
`playerId` in the envelope or the payload. The command is rejected, without
changing any state, when:

| Condition | Code |
|---|---|
| The connection is not a live, connected member | `NOT_ROOM_MEMBER` |
| No match is running | `MATCH_ALREADY_FINISHED` |
| `matchId`, `turnNumber` or `expectedStateVersion` is stale | `STATE_VERSION_CONFLICT` |
| The sender does not own the live turn, or the deadline already passed | `NOT_YOUR_TURN` |
| No living opponent is left to shoot at | `TARGET_NOT_ALIVE` |
| The cell is outside the board | `INVALID_TARGET_CELL` |
| A field is missing or has the wrong type | `MALFORMED_PAYLOAD` |

The no-repeat rule is **per attacker on the shared map**: two different
players may fire at the same cell, and each of them may fire at any given cell
only once, whichever fleet it hits.

An accepted shot commits the damage, the next actor and the new turn deadline
before the first frame is written, so a concurrent command or a deadline tick
can never consume the same turn twice. The state version increases exactly
once.

### Combat events

| Event | Recipients | Payload |
|---|---|---|
| `game:shot-result` | The attacker and every target of the volley | `attackerPlayerId`, `targetPlayerId`, `row`, `column`, `result` (`miss`, `hit`, `shipSunk`). The attacker receives **one** event that aggregates the volley and names the target with the strongest result; each target receives its own impact together with its `ownBoard`. The `requestId` is echoed to the attacker only |
| `game:public-activity` | Every player who was not part of the volley | `attackerPlayerId`, `targetPlayerId`, `result` — no coordinates and no ship data. On the shared map the attacker and every living opponent take part in each shot, so this feed reaches eliminated spectators only |
| `game:turn-started` | Everybody | `activePlayerId`, `turnNumber`, `remainingSeconds` |
| `game:player-eliminated` | Everybody | `playerId`, `displayName` |
| `game:state-snapshot` | Everybody, one filtered view each | `snapshot` — see below |
| `game:finished` | Everybody | `matchId`, `stateVersion`, `winnerPlayerId`, `winnerDisplayName`, `durationSeconds`, `ranking[]` — see below |

### `game:state-snapshot`

The Host sends a permission-filtered view of the match to every client after
each accepted change:

```json
{
  "messageType": "game:state-snapshot",
  "payload": {
    "snapshot": {
      "matchId": "match-uuid",
      "stateVersion": 15,
      "turnNumber": 6,
      "activePlayerId": "player-uuid",
      "turnRemainingSeconds": 30,
      "players": [
        { "playerId": "player-uuid", "displayName": "Alice", "alive": true, "timeouts": 0, "shipsRemaining": 4 }
      ],
      "ownBoard": {
        "ships": [
          {
            "shipId": "ship-1", "length": 4, "orientation": "horizontal",
            "row": 0, "column": 0, "hitCells": [ { "row": 0, "column": 1 } ],
            "sunk": false
          }
        ],
        "shotsReceived": [ { "row": 0, "column": 1 } ]
      },
      "mapShots": [
        { "row": 0, "column": 0, "result": "hit", "attackerPlayerId": "player-uuid" }
      ],
      "sunkShips": [
        {
          "ownerPlayerId": "other-uuid", "shipId": "ship-2", "length": 2,
          "orientation": "vertical", "row": 4, "column": 6
        }
      ],
      "winnerPlayerId": null
    }
  }
}
```

`ownBoard` is the exact fleet of the recipient, and the client draws those
hulls on the same board as `mapShots`. `mapShots[]` is the single shared
battle map: every shot of every player, one mark per shooter and cell,
carrying the strongest result the shot had on any fleet and the
`attackerPlayerId` that fired it. That is how the client paints one colour per
shooter. The **layout** of a fleet never leaves the Host except in that
player's own view; the hits on it do become public, because the shared map
shows where every shot landed. The player list follows the turn order, not
the join order.

`sunkShips[]` lists every ship of every fleet that is already sunk, with its
`ownerPlayerId` and its placement. Only sunk ships are published: every one of
its cells was hit, and every hit is already a public mark on the shared map,
so the outline adds no information the room did not have. The client draws
them as faded outlines in the colour of the player who owned them. Fleets that
are still afloat never leave the Host, so `sunkShips[]` is empty until the
first ship goes down.

`shipsRemaining` is aggregate status: the number of ships of that fleet that
are still afloat. It carries no coordinate and no ship position, so every
player may see it. The public activity events already announce every sunk
ship, so the count reveals nothing that was not public before.

An eliminated player receives the same filtered snapshot — their own sunk
fleet and the public map — plus `alive: false` in `players[]`. That flag is
what turns their UI into the read-only spectator view: no battle board and no
fire action. They never receive another player's fleet, and the Host rejects
any fire command from them with `NOT_YOUR_TURN`.

### The turn deadline

The Host owns the turn deadline exactly like the preparation deadline. The
`host:heartbeat` carries `turnRemainingSeconds` while a turn is running, and
a client that runs out of time simply has its turn skipped: the player is not
eliminated for a single timeout, and the number of timeouts per player is
reported in `players[]`.

### `game:finished`

The Host sends the final result once exactly one player is left alive. The
payload is identical for every recipient: the ranking and the statistics are
Host truth and no client recomputes them.

```json
{
  "messageType": "game:finished",
  "payload": {
    "matchId": "match-uuid",
    "stateVersion": 42,
    "winnerPlayerId": "player-uuid",
    "winnerDisplayName": "Alice",
    "durationSeconds": 272,
    "ranking": [
      {
        "playerId": "player-uuid", "displayName": "Alice", "rank": 1,
        "shots": 18, "hits": 11, "misses": 7, "shipsSunk": 5, "timeouts": 0
      },
      {
        "playerId": "player-uuid", "displayName": "Bob", "rank": 2,
        "shots": 14, "hits": 8, "misses": 6, "shipsSunk": 3, "timeouts": 1
      }
    ]
  }
}
```

| Field | Meaning |
|---|---|
| `matchId` | The match the result belongs to |
| `stateVersion` | The final room state version, incremented exactly once by the winning shot |
| `winnerPlayerId`, `winnerDisplayName` | The last player alive. `null` when nobody survived |
| `durationSeconds` | From the first turn to the moment the match ended, measured with the Host clock |
| `ranking[]` | Every player of the match, ordered from the winner down |

The ranking is the winner first, then the eliminated players in **reverse
elimination order**: the fleet that sank last places second. Every player
appears exactly once.

Statistics are counted per accepted shot. A sinking shot counts as a hit as
well, so `shots == hits + misses` always holds, and `shipsSunk` counts the
ships the player sank, not the ships they lost. `timeouts` is the number of
turns the player let expire. A rejected shot never changes any number.

The event is followed by a `game:state-snapshot` carrying `winnerPlayerId`
and by a `room:state` with `status: "finished"`. The room stays open: the
Host closes it explicitly, and a client leaves it, from the result screen.

## 9. Heartbeats and host loss

- The Host sends `host:heartbeat` approximately every 3 s. The event
  carries the current `stateVersion`, plus `placementRemainingSeconds` while
  the preparation runs and `turnRemainingSeconds` while a turn runs.
- Clients track the time since the last valid Host heartbeat using a monotonic
  timer.
- After roughly 8–10 s without a heartbeat, the client marks the room
  `ABORTED_HOST_LOST` and returns Home.
- On an explicit close, the client reacts to `room:closed` / `game:aborted`
  immediately and does not wait for the timeout.
- No automatic Host election, transfer or migration is ever attempted.

---

## 10. Shot resolution order

The Host applies a shot atomically inside its state coordinator:

1. Resolve the sender's identity from the accepted TCP connection.
2. Confirm the room and match are active.
3. Confirm the sender owns the current turn.
4. Confirm the target is alive and is not the attacker.
5. Validate row and column bounds.
6. Check whether this attacker already fired at this target cell.
7. Resolve `MISS`, `HIT` or `SHIP_SUNK` from Host-owned fleet data.
8. Update statistics and target ship state.
9. Determine whether the target is eliminated.
10. Determine whether the match has a winner.
11. If the match continues, select the next living player and set a new deadline.
12. Increment the state version exactly once for the accepted command.
13. Emit permission-filtered events to the attacker, the target and the rest.
14. Acknowledge the sender.

State-changing commands are serialized through a single coordinator so two
commands can never consume the same turn concurrently. The commit of steps 7
to 12 happens before the first frame of step 13 is written, so an accepted
shot can never be observed in a half-applied state, and a command that was
already rejected never damages a board.
