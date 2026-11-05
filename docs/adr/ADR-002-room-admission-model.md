# ADR-002 — Room admission model

- **Status:** Accepted
- **Date:** 2026-11-05
- **Phase:** 1 (PLAN.md §15, Phase 1)
- **Affects:** `lib/host_runtime/**`, `lib/features/rooms/**`, `lib/shared/models/room_models.dart`

---

## Context

Phase 1 turns the Phase 0 transport into a real room: one device hosts, other
devices join with an invitation code, and the Host admits or rejects them.

PLAN.md §7.3 requires that *"a player cannot join the same room more than once
under multiple active connections"*, and §8.3 states that `room:joined` carries
a resume token. §12 requires that room codes and session tokens come from a
cryptographically secure random source and that they are never logged.

The plan does not say how the Host recognises a returning device, because the
answer depends on whether the resume flow is already in place. In Phase 1 the
reconnect-and-resume flow itself is explicitly Phase 7 work.

---

## Decision 1 — The join handshake carries a local `deviceId`

**The client sends a locally generated `deviceId` in the `room:join` payload.
The Host rejects a second concurrent connection from a device that already
holds a seat, with `DEVICE_ALREADY_CONNECTED`.**

### Rationale

- The rule in §7.3 has to be enforced at join time, because Phase 1 does not
  yet implement `session:resume`. The only identifier available at that point
  is one the device brings with it.
- A `deviceId` is a random 24-character string generated once by
  `LocalPreferences` and stored on the device. It is **not** an account, not a
  cloud identity, and it never leaves the local network. §4.2 lists
  "cross-device account sync and server-issued identities" as out of scope, and
  this stays well clear of that line.
- A nickname would be a poor substitute: two players may legitimately share a
  name, and a name can be changed at any time.

### Consequences

- The device identifier is part of the wire contract. It is documented in
  `LAN_PROTOCOL.md` §8.1.
- A player who leaves the room frees their seat, because only members whose
  status is `connected` or `disconnected` occupy a seat. The same device may
  therefore rejoin after leaving.
- The Host-side duplicate check runs **before** the capacity check, so the
  error a player sees is the one that describes their actual situation.

---

## Decision 2 — The resume token is issued now, used from Phase 7

**The Host issues a resume token in `room:joined` and stores only its SHA-256
hash. The token is used by `session:resume` from Phase 7 on.**

### Rationale

- `room:joined` is specified to carry the resume token, and the Host must be
  able to accept the token later without a protocol change. Issuing it now
  avoids a breaking change in Phase 7.
- Storing only the hash means a memory dump of the Host process does not
  reveal a usable token, which satisfies the intent of §12 ("do not log room
  resume tokens").

### Consequences

- The client session exposes the token so the Phase 7 implementation can
  persist it locally.
- The token is never sent back to the Host in Phase 1 and never appears in any
  projection.

---

## Decision 3 — The Host broadcasts per-recipient projections

**Every client receives its own `RoomSnapshot` through `ProjectionBuilder`.
The Host never serializes its internal state once and sends it to everybody.**

### Rationale

- §6.4 and §6.6 forbid broadcasting one serialized state, because the Host's
  internal state contains the complete fleet layouts of every player.
- The lobby projection is small, so the cost of building one projection per
  recipient (at most six) is negligible, and it keeps the rule true from the
  first release rather than retrofitting it later.
- The projection carries `viewerPlayerId` and `viewerIsHost`, so the Host
  badge on the client is decided by the Host and cannot be spoofed by a
  modified client.

### Consequences

- A change produces one `room:state` message per recipient. The payload is a
  few hundred bytes, which is irrelevant on a LAN.
- `stateVersion` increases exactly once per accepted change, and every
  projection carries it, so a client can detect a missed update.

---

## Decision 4 — Capacity counts seated members, not rows

**The capacity check counts members whose status is `connected` or
`disconnected`. Members that left or were removed do not occupy a seat.**

### Rationale

- A member who left may rejoin, and a removed member must not keep a seat.
- The Host itself occupies one seat: it is a normal participant and can be
  eliminated or win (§2.1).

---

## Decision 5 — The Host heartbeat and the client watchdog ship in Phase 1

**The Host sends `host:heartbeat` every 3 s. The client declares the Host lost
after 10 s of silence and returns Home. The full reconnect-and-resume flow
stays in Phase 7.**

### Rationale

- Without a heartbeat, an idle lobby gives the client no signal at all, and a
  crashed Host looks exactly like a healthy one. The watchdog is small and
  uses the constants already frozen in `AppProtocol`.
- The full resume flow — grace period, seat restoration, permission-filtered
  snapshot on reconnect — is Phase 7 work and is not started here.

### Consequences

- The client shows a clear "the host is unreachable" state instead of
  hanging on a dead socket.
- Phase 7 replaces the simple watchdog with the grace-period logic and adds
  the `session:resume` command handling.

---

## Consequences summary

| Concern | Where it lives |
|---|---|
| Room rules and admission | `lib/host_runtime/room_coordinator.dart` |
| Network plumbing | `lib/host_runtime/host_room_service.dart` |
| Per-recipient views | `lib/host_runtime/projection_builder.dart` |
| Connection bookkeeping | `lib/host_runtime/client_connection_registry.dart` |
| Client side of the handshake | `lib/features/rooms/data/room_client_session.dart` |
| Local identity | `lib/core/storage/local_preferences.dart` |

---

## Follow-ups

| # | Task | Phase |
|---|---|---|
| 1 | Implement `session:resume` with the 30 s grace period | 7 |
| 2 | Persist the resume token locally and send it on reconnect | 7 |
| 3 | Rate-limit failed join attempts per connection | 9 |
| 4 | Show the seat count and the capacity in the lobby | 2 |
| 5 | Add the Host settings screen on top of `hostUpdateConfig` | 2 |
