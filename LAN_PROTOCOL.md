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
  "protocolVersion": 1,
  "messageType": "game:fire",
  "requestId": "local-uuid",
  "roomId": "room-uuid",
  "playerId": "player-uuid",
  "expectedStateVersion": 24,
  "payload": {
    "targetPlayerId": "target-player-uuid",
    "row": 3,
    "column": 7
  }
}
```

| Field | Required | Meaning |
|---|---|---|
| `protocolVersion` | yes | Integer protocol version. Currently `1`. |
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
| `placement:set` | Place or move a ship | Sender owns the board; placement phase active; placement valid |
| `placement:auto` | Request automatic placement | Sender owns the board; placement phase active |
| `placement:ready` | Confirm a complete fleet | All ships placed legally |
| `game:fire` | Fire at a coordinate | Active turn owner; living target; valid cell; no repeated shot |
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
| `room:closed` | Host explicitly closed the room or ended the match |
| `placement:started` | Placement deadline and fleet profile |
| `placement:state` | Caller-specific placement status |
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
| `game:finished` | Winner, ranking and final statistics |
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

A `protocol:error` never carries stack traces, local file paths, raw exception
text or private fleet data.

---

## 8. Information visibility

- Never send another player's complete fleet layout to an opponent.
- During placement, a player receives their own exact fleet layout and other
  players' readiness only.
- During a match, the target receives impact coordinates for shots against
  their own board; the attacker receives the result of their own shot.
- Other players receive public match events and aggregate status only.
- Eliminated players receive a restricted spectator projection.
- Client clocks, turn counters, hit calculations, ship counts and match status
  are never trusted. The Host owns all of them.
- Host-side complete state stays separate from serialized client view models.
- Resume tokens and full fleet layouts are never logged.

---

## 9. Heartbeats and host loss

- The Host sends `host:heartbeat` approximately every 3 s.
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
commands can never consume the same turn concurrently.
