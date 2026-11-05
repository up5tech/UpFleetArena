# UpFleet Arena — Product & Technical Implementation Plan

> **Document status:** Approved MVP direction after LAN-only decision  
> **Product type:** Local-network, turn-based, 2D multiplayer naval combat game  
> **Client:** Flutter / Dart (Android and iOS first)  
> **Networking:** Local Wi-Fi only; device discovery with mDNS/Bonjour; direct TCP sockets  
> **Authority:** The room creator's phone is the Host and runs the complete game authority  
> **Backend:** None — no NestJS, cloud game server, hosted database, or Internet dependency  
> **Host exit policy:** The match/room ends when the Host exits or becomes unreachable; no host migration

---

## 1. Product Overview

### 1.1 Vision

Build a mobile 2D multiplayer strategy game in which one player creates a private room on a local Wi-Fi network, shares a short invitation code with nearby friends, configures the battlefield and fleet rules, and hosts the game directly from their phone. Other players discover the Host on the same local network and join the room using the code.

Each participant secretly positions ships on their own board before the preparation timer expires. Once everyone is ready—or the preparation deadline is reached—the Host starts the match. Players take turns firing at living opponents' boards. A ship is sunk when all of its cells have been hit. The match ends when only one player still has at least one surviving ship.

The experience should feel like a modern, animated, mobile-first, free-for-all Battleship game, with clear turn feedback, satisfying hit effects, and reliable synchronization over a local Wi-Fi network.

### 1.2 Approved product and technical constraints

The following decisions are confirmed and must be treated as requirements, not open questions:

1. **LAN-only multiplayer:** Players must be connected to the same local Wi-Fi/LAN. The game does not support Internet matchmaking or remote players in this release.
2. **No backend:** Do not build, deploy, or depend on NestJS, Firebase, Supabase, a cloud API, a hosted game server, PostgreSQL, Redis, or another central service.
3. **Host-authoritative:** The device that creates the room is the Host. It runs the room lifecycle, game rules, timers, validation, and result calculation.
4. **Direct local connections:** Every participant connects directly to the Host over the local network. Clients do not need to connect to one another.
5. **Host exit ends the game:** If the Host explicitly exits, closes the room, closes the app, crashes, loses Wi-Fi, or becomes unreachable, the current room/match is terminated for every participant. There is no host migration.
6. **Local persistence only:** Preferences and personal match history may be saved on each device. An active match is held in Host memory and is not recoverable after the Host process terminates.
7. **No Internet required:** Room discovery, joining, gameplay, timers, and match results must work when the Wi-Fi router has no Internet connection, provided the local network allows device-to-device traffic.

The Host phone is technically running a small in-process TCP game server, but this is **not a separately deployed backend**. It exists only while the Host app is hosting a room.

### 1.3 Important LAN limitation

“Same Wi-Fi” is necessary but not always sufficient. Some routers, guest Wi-Fi networks, corporate networks, and mobile hotspots enable client/AP isolation or block multicast discovery. In those environments, devices may be unable to see or reach each other even though they display the same Wi-Fi name.

The MVP must detect and explain connection failures. Provide a manual connection fallback (Host local IP/port and/or QR connection card) where practical, but do not silently introduce Internet signaling or cloud services.

### 1.4 Working title

**UpFleet Arena** is the working title. It can be renamed without affecting the architecture.

### 1.5 Core user journey

1. A player opens the app and enters a nickname, or restores a nickname saved locally.
2. The player chooses **Create Room** or **Join Room**.
3. The Host creates a room. The app opens a TCP listener on the Host phone and advertises a local-network service.
4. The Host receives a short invitation code and shares it with nearby friends.
5. Other players scan for UpFleet rooms on the same Wi-Fi, select the matching Host/room label, enter the invitation code, and connect directly to the Host.
6. The Host configures board dimensions, fleet preset, preparation duration, turn duration, and player capacity.
7. The Host starts placement when the room has enough players.
8. Every player places ships on their own private board and presses **Ready**.
9. The match starts when everyone is ready or when the placement timer expires.
10. The Host selects the first player and publishes the turn order.
11. On each turn, the active player chooses a living opponent and a cell on that opponent's board, then presses **Fire**.
12. The Host validates the command, calculates the outcome, updates the authoritative state, and sends each player only the information they are allowed to see.
13. Eliminated players can watch public match activity but cannot fire again.
14. The last player with surviving ships wins.
15. The Host broadcasts the final result and closes the room when everyone leaves or the Host chooses to close it.

---

## 2. Recommended Game Rules for the First Release

The original concept leaves a few game details open. This plan adopts one coherent baseline so development can proceed without repeatedly changing the rules. These are gameplay defaults and can be adjusted before implementation.

### 2.1 Match format

- **Mode:** Private-room, free-for-all naval combat.
- **Players:** 2–6 recommended for the first release. Keep the data structures flexible enough to support 8 later, but do not increase the MVP cap without device testing.
- **Minimum to start:** 2 connected, eligible players including the Host.
- **Room invitation:** A locally generated, random 6-character alphanumeric code. Exclude visually ambiguous characters such as `0`, `O`, `1`, and `I`.
- **Accounts:** No accounts, login, cloud identity, or registration. Each device stores a local guest profile (nickname and avatar).
- **Spectators:** Eliminated players remain connected as read-only spectators. New players cannot join after placement begins.
- **Public matchmaking:** Not supported. Rooms are discovered only on the same LAN and require the invitation code.
- **Host role:** The Host is also a normal participant and can place ships, take turns, be eliminated, and win. The Host additionally has authority over the room and full game state.

### 2.2 Battlefield model

Use **one private board per player**, rather than one shared board for the entire room:

- Every player places their own fleet on their own grid.
- During a turn, the active player selects a living opponent, then selects a coordinate on that opponent's grid.
- The target player receives the impact notification and sees the hit or miss on their own board.
- The attacker sees the result of their own shot and records it on their attack history for that target.
- Other players receive a limited public activity event, such as “Player A hit Player B”, but do not receive hidden ship positions or exact coordinates.
- The Host stores all complete fleet layouts because it must validate and resolve shots. This creates an unavoidable trust limitation: a technically curious or malicious Host can inspect hidden fleet data.

This is the recommended multiplayer Battleship free-for-all model and supports the last-player-standing rule cleanly. A single shared map would be a different game mode and is out of MVP scope.

### 2.3 Board dimensions

The Host selects the board size before placement begins.

| Setting | Default | MVP range |
|---|---:|---:|
| Columns | 10 | 8–14 |
| Rows | 10 | 8–14 |
| Board shape | Square | Square or rectangle |
| Cell shape | Square | Fixed square cells; the board may scroll or scale |

Store `rows` and `columns` independently even if the first UI exposes only a few square presets. The game engine must validate rectangular boards as well.

### 2.4 Fleet configuration

The Host chooses a fleet preset that determines both ship count and ship lengths. A raw ship count is insufficient because placement validation and sinking rules depend on each ship's length.

| Preset | Ship lengths | Ship count |
|---|---|---:|
| Small Fleet | `[3, 2, 2]` | 3 |
| Standard Fleet | `[4, 3, 3, 2, 2]` | 5 |
| Large Fleet | `[5, 4, 3, 3, 2, 2]` | 6 |

Rules:

- Ships are straight and occupy consecutive cells horizontally or vertically.
- Ships may not overlap.
- Ships may touch each other in MVP; diagonal and edge adjacency are allowed.
- Every ship must be fully inside the board.
- Fleet profiles must pass a fit check for the selected board dimensions.
- Custom fleet editing can be added after the preset-based MVP is stable.

### 2.5 Placement phase

- The Host chooses a preparation duration. Recommended range: **60–180 seconds**, default **120 seconds**.
- The Host is the only authority for the placement deadline. Client countdowns are visual estimates.
- Every player places all ships on their own board.
- Players can rotate ships between horizontal and vertical orientation.
- Provide manual placement and **Auto Place**.
- The **Ready** button is enabled only after the entire fleet is placed legally.
- A ready player cannot change the fleet after readiness is confirmed unless the Host resets the placement phase.
- The match starts immediately when every connected, eligible player is ready.
- When the timer expires, the Host automatically completes incomplete fleets with a validated random placement algorithm and marks those players ready. Communicate this rule in the lobby and placement UI.
- If fewer than two eligible players remain when the timer expires, cancel the match and return to the lobby.

### 2.6 Turn order and firing

- The Host randomly chooses the first player after placement completes.
- Remaining players receive a randomized order.
- Turns proceed in a circular order.
- Eliminated or forfeited players are skipped automatically.
- Each turn allows **one shot**, regardless of hit or miss. A hit does not grant an extra shot in MVP.
- The active player chooses any living opponent except themselves, then chooses one cell on that opponent's board.
- A cell can be fired at only once per attacker-target pair in MVP. The Host validates this rule.
- The Host resolves the shot and returns one of: `MISS`, `HIT`, or `SHIP_SUNK`.
- A player is eliminated when every cell of every ship in their fleet has been hit.
- When one player remains alive, that player wins and the match ends.

### 2.7 Turn deadline

Add a per-turn timer to prevent a stalled match.

- Recommended default: **30 seconds**.
- Suggested Host-configurable range: 15–60 seconds.
- The Host starts and owns every turn deadline. Clients render a countdown based on the most recently received remaining duration/deadline information.
- If a player does not fire before the deadline, the Host skips their turn and advances to the next living player.
- Consecutive timeout count is tracked and displayed. Do not eliminate a player solely for one timeout in MVP.
- A player who repeatedly times out may be removed/forfeited by the Host under a clearly documented room rule. Keep this out of the initial game loop unless testing shows it is needed.

### 2.8 Non-host disconnect policy

The Host remains the authority as long as its app is running and reachable.

- If a non-host player disconnects temporarily, the Host keeps that player's fleet and match state in memory.
- Allow that player to reconnect to the same Host and reclaim their seat using a short-lived, randomly generated player resume token stored locally on that device.
- Recommended reconnect grace period: **30 seconds**.
- If the disconnected player owns the active turn, the Host may pause that player's turn timer for at most the reconnect grace period. If they do not return, skip the turn and mark them disconnected; a later explicit forfeit policy may eliminate them.
- If a disconnected player reconnects before the grace period ends, the Host sends a fresh permission-filtered state snapshot.
- If a non-host player does not reconnect, the Host may continue the match with the player marked disconnected. Do not allow the client to declare another player eliminated.
- No cloud state is available. If the Host app terminates, no client can recover the active match.

### 2.9 Host exit and Host loss policy — confirmed

**There is no host migration. A Host exit terminates the room and match.**

- When the Host taps **Exit Room**, **Close Room**, or **End Match**, the Host first broadcasts a `room:closed` or `match:aborted` event with a user-safe reason, then closes all client sockets, stops LAN service advertising, and closes its TCP listener.
- If the Host app is force-closed, crashes, loses Wi-Fi, or otherwise becomes unreachable before broadcasting the event, clients detect the missing Host heartbeat and show **Host disconnected — match ended**.
- Use a heartbeat interval of approximately 3 seconds and an unreachable timeout of approximately 8–10 seconds. The timeout is only for detecting an abrupt failure; it is not a reconnect grace period for the Host.
- Once the Host is determined to be unavailable, every client marks the match `ABORTED_HOST_LOST`, returns to the home screen, and clears active-room state. A client must not attempt to elect a new Host or continue the game independently.
- The Host must remain in the foreground during hosting. Mobile operating systems can suspend background work; the app should warn the Host before leaving the foreground and keep the screen awake while hosting where appropriate.

### 2.10 Match end

The Host creates and broadcasts a final result containing:

- Winner player ID and display name.
- Final player ranking / elimination order.
- Match duration.
- Per-player statistics: shots, hits, misses, ships sunk, and timeouts.
- A locally generated match ID and final state version.

Each device may save a copy of the final result to its own local history. There is no central match-history service. Provide **Play Again** as a post-MVP enhancement; MVP may return everyone to the home screen or let the Host create a fresh room with the previous configuration prefilled.

---

## 3. Room Configuration and Host Permissions

### 3.1 Host controls

The Host can:

- Create and close the room.
- Share the room invitation code.
- Edit board size before placement starts.
- Choose a fleet preset.
- Set placement duration.
- Set turn duration.
- Set the room maximum player count (within supported limits).
- Start placement when at least two eligible players are connected.
- Kick a player from the lobby before the match starts.
- Reset placement if the room is still in the placement phase and the rules permit it.
- End the match at any time; this terminates the room for all participants.

Host transfer is explicitly not supported.

### 3.2 Non-host permissions

Other players can:

- Discover available UpFleet rooms on the same LAN.
- Enter the room code and request to join.
- Change their display name before the match starts.
- View room configuration and player readiness.
- Place and rotate their own ships during the placement phase.
- Use Auto Place.
- Confirm Ready or request an unready/reset action if Host policy permits it.
- Leave the room before or during a match. Leaving during a match follows the non-host disconnect/forfeit policy.

Players cannot modify room configuration, another player's fleet, turn order, shot outcomes, or match state.

### 3.3 Room lifecycle

```text
HOST_HOME
   |
   | Create Room
   v
HOST_LISTENING_AND_ADVERTISING
   |
   | LAN clients discover service and join with code
   v
LOBBY_CONFIGURING
   |
   | Host starts placement
   v
PLACEMENT_ACTIVE
   |
   | All ready OR preparation deadline reached
   v
MATCH_ACTIVE
   |
   | Only one living player remains
   v
MATCH_FINISHED
   |
   | Host closes room / everyone leaves
   v
ROOM_CLOSED
```

Terminal alternatives:

- `ROOM_CANCELLED`: Host closes the lobby before the match starts or fewer than two eligible players remain.
- `MATCH_ABORTED_HOST_EXIT`: Host explicitly ends the active match.
- `MATCH_ABORTED_HOST_LOST`: clients detect that the Host app/device is no longer reachable.

There is no room persistence beyond the Host process. When the Host process exits, the room is gone.

---

## 4. Functional Scope

### 4.1 MVP features

1. Local guest profile (nickname and avatar) stored on the device.
2. Create a room on the Host phone.
3. Generate a random invitation code locally.
4. Start a TCP listener on the Host phone and advertise the room over mDNS/Bonjour.
5. Discover nearby rooms on the same LAN.
6. Join by selecting a discovered room and entering its invitation code.
7. Optional manual endpoint / QR fallback when automatic discovery is blocked by the Wi-Fi network.
8. Real-time lobby player list and Host indicator.
9. Host room configuration.
10. Kick/leave/close-room controls in the lobby.
11. Private ship placement with rotation, drag/tap, Auto Place, and Ready.
12. Host-authoritative placement deadline and timeout behavior.
13. Randomized turn order.
14. Target selection among living opponents.
15. Host-authoritative shot validation and hit/miss/sunk calculation.
16. Elimination and winner detection.
17. Turn timer and timeout handling.
18. Non-host disconnect/reconnect within a short grace period.
19. Immediate Host termination behavior with client-side Host-loss detection.
20. Local result history and user preferences.
21. Sound, haptics, animation, and accessibility settings.

### 4.2 Explicitly out of scope

- Internet multiplayer and remote players outside the same LAN.
- Cloud room discovery or global room lists.
- Any hosted signaling service, matchmaking service, or game server.
- NestJS or another separate backend application.
- Firebase, Supabase, PostgreSQL, Redis, or cloud database dependencies.
- Host migration or continuation after the Host exits.
- Cross-device account sync and server-issued identities.
- Global leaderboards, seasons, clans, tournaments, and cloud achievements.
- In-game text chat and voice chat.
- Spectators joining after the match starts.
- Multiple regional servers or relay infrastructure.
- Multiple weapon types, area attacks, mines, shields, and special abilities.
- Advanced replay viewer.
- AI opponents in the multiplayer room (a separate offline practice mode may be considered later).

---

## 5. UX and Screen Plan

### 5.1 Visual direction

- Modern 2D naval strategy theme, not a realistic military simulator.
- Strong contrast between water, ship cells, hit cells, miss cells, selected cells, and disabled cells.
- Use a restrained blue/navy palette with bright accent colors for turn ownership and attack feedback.
- Use subtle ocean/wave backgrounds, grid transitions, projectile trails, splash effects, and ship-sinking animations.
- Keep animations short and never block the next required action.
- Support sound and haptic settings independently.
- Make the UI readable on smaller phones and tablets.

### 5.2 Required screens

| Screen | Responsibilities |
|---|---|
| Splash / Bootstrap | Load local preferences, restore nickname/avatar, initialize LAN permission status when needed. |
| Home | Create Room, Join Room, Settings, How to Play. |
| Guest Profile | Enter/edit nickname and select a simple avatar. |
| Create Room | Create the Host session, show local-network availability and invitation code. |
| Discover Rooms | Scan for local UpFleet services, show discovered rooms and scan status. |
| Join Room | Enter room code, validate against the selected local Host, and show connection feedback. |
| Manual Connect | Optional IP/port or QR-based fallback when mDNS discovery is blocked. |
| Lobby | Player list, Host badge, room code/share action, settings, readiness indicators. |
| Host Settings | Board dimensions, fleet preset, player capacity, placement timer, turn timer. |
| Ship Placement | Player's own board, ship inventory, rotation, drag/tap placement, Auto Place, Ready. |
| Turn Intro | Active player, target selection, countdown, turn order context. |
| Target Selection | List/grid of living opponents and their remaining fleet status (without hidden coordinates). |
| Battle Board | Target's board view, selectable cells, previous shots by the current attacker, Fire action. |
| Shot Result | Hit/miss/sunk animation and clear next-turn transition. |
| Spectator View | Match status, public activity, remaining players, read-only public information. |
| Match Result | Winner, elimination ranking, match statistics, Save Result, Return Home. |
| Settings | Sound, music, haptics, language, display options. |
| LAN Permission / Connection Overlay | Explain local-network permission, discovery failure, Wi-Fi mismatch, Host disconnection, and aborted match. |

### 5.3 Board interaction

- Use a scalable grid renderer rather than creating hundreds of complex widget instances.
- Flutter `CustomPainter` is sufficient for the first release; a full game engine is not required for a turn-based grid game.
- Use a gesture layer to map tap/drag coordinates to row and column.
- Keep board state separate from paint logic.
- Use a minimum interactive cell size; on narrow screens, allow zoom or board panning rather than making cells too small.
- In placement mode, visually distinguish unplaced ships, valid preview cells, invalid preview cells, placed ships, and the selected ship.
- In attack mode, show only information the active player is allowed to know.

### 5.4 LAN UX and permission handling

- Explain clearly that all players must be connected to the same Wi-Fi/LAN. Internet access is not required.
- Before scanning, request the platform's local-network permission where required.
- On iOS, explain why the app needs Local Network access and Bonjour discovery.
- On Android versions that require it, request local-network access before creating or connecting sockets.
- If discovery returns no rooms, show troubleshooting steps: verify same Wi-Fi, disable guest Wi-Fi/client isolation, check VPN settings, keep Host app open, and try manual IP/QR connection.
- Do not label a room “offline” merely because Internet access is missing. LAN play is expected to work without Internet.
- Show Host status prominently. Tell all participants that closing the Host app ends the match.
- While hosting, warn before backgrounding or closing the app. Keep the display awake where appropriate and provide an obvious **End Room** action.

### 5.5 Accessibility and usability

- Do not rely on color alone to communicate hit/miss/ready states; use icons and text labels too.
- Provide scalable text and adequate touch targets.
- Respect device safe areas and system text scaling.
- Support reduced-motion settings where practical.
- Provide clear feedback for invalid placements, duplicate shots, expired timers, denied permissions, failed discovery, and Host loss.

---

## 6. Technical Architecture

### 6.1 Recommended stack

#### Flutter application

- Flutter / Dart.
- State management: Riverpod.
- Navigation: GoRouter.
- LAN service discovery and advertisement: **Bonsoir** (`bonsoir`) or `nsd`; run a real-device proof of concept before finalizing the package.
- Transport: Dart standard library `dart:io` using `ServerSocket` on Host and `Socket` on clients.
- Runtime permission handling: `permission_handler`, especially for Android local-network access on OS/API versions where it is required.
- Serialization: `json_serializable` and optionally Freezed for immutable DTOs/state.
- Non-sensitive preferences: `shared_preferences`.
- Local match history: SQLite via `drift` or another maintained local-only solution; this is not required for the first playable build.
- Grid rendering: Flutter Canvas / `CustomPainter`.
- Optional screen-awake support: a maintained wakelock package, enabled only while the device is hosting or otherwise required by gameplay.
- Optional audio: a maintained Flutter audio package selected during implementation.

#### Host runtime (inside the Flutter app)

The Host phone runs these in-process components:

- `LanRoomHost`: binds a local TCP listener and accepts client connections.
- `LanDiscoveryAdvertiser`: advertises the active room via mDNS/Bonjour.
- `RoomCoordinator`: owns room membership, host permissions, and room lifecycle.
- `GameEngine`: pure domain rules for placement, shots, turns, elimination, and victory.
- `MatchStateStore`: holds the complete active room/match state in memory.
- `HostTimerController`: owns placement and turn deadlines.
- `ClientConnectionRegistry`: tracks connected sockets, heartbeat state, and client identities.
- `ProjectionBuilder`: creates a different state view for each recipient so hidden ship positions are not sent to other clients.

These components are libraries/services within the Flutter app. They are not separately deployed services and do not require a backend repository.

### 6.2 LAN transport and topology

Use a **star topology**:

```text
+-------------------------+
| Host Flutter App        |
|                         |
| RoomCoordinator         |
| GameEngine              |
| MatchStateStore         |
| HostTimerController     |
| ServerSocket (TCP)      |
| mDNS / Bonjour Advert.  |
+------------+------------+
             |
       Local Wi-Fi / LAN
             |
     +-------+--------+----------------+
     |                |                |
+----v-------+  +-----v------+  +------v-----+
| Client 2   |  | Client 3   |  | Client N   |
| Flutter    |  | Flutter    |  | Flutter    |
| TCP Socket |  | TCP Socket |  | TCP Socket |
+------------+  +------------+  +------------+
```

Every client communicates only with the Host. Do not build a full mesh in which every player maintains connections to every other player. Star topology reduces connection complexity, centralizes the state authority, and matches the approved Host-exit policy.

### 6.3 Room discovery and joining flow

1. Host generates a cryptographically random room code locally.
2. Host binds `ServerSocket` to an available port on the local network interface (initially use an ephemeral port rather than hard-coding one).
3. Host advertises a Bonjour/DNS-SD service using a dedicated service type such as `_upfleet._tcp`. Advertise a non-secret room label or Host nickname, not the invitation code.
4. The invitation code must not be embedded in the public mDNS service name or other discovery metadata. Every device on the same LAN may be able to inspect discovery announcements.
5. A joining client scans for `_upfleet._tcp`, resolves the selected service, and obtains the Host address(es) and port. The discovery list displays a room label/Host nickname so users can select the intended room.
6. The client enters the invitation code and sends a `room:join` handshake over TCP.
7. Host validates protocol version, room code, room phase, player capacity, nickname, and join eligibility.
8. Host accepts the player and returns a filtered room snapshot, or returns a stable error code.
9. Host stops advertising when the room closes or the Host process exits.

The UI should support entering the code after the user selects a discovered room. The code is checked only by the selected Host during the TCP handshake; it is not part of LAN discovery metadata. Do not assume `.local` hostname resolution works on every OS; prefer resolved service IP addresses and correctly handle IPv4/IPv6.

### 6.4 Direct TCP protocol

Use one long-lived TCP connection from each client to the Host for the room session.

- Use a documented, versioned application protocol.
- Use **length-prefixed JSON frames** (for example, a 4-byte unsigned big-endian payload length followed by UTF-8 JSON) or another explicitly framed format. Do not assume one TCP read equals one full message.
- Set a maximum inbound frame size (for example, 64 KiB) and reject oversized or malformed frames.
- Include `protocolVersion`, `messageType`, `requestId`, `roomId`, `playerId` where applicable, `expectedStateVersion` where applicable, and `payload`.
- Include request/response correlation IDs so clients can match acknowledgements to commands.
- TCP is ordered and reliable while connected, but the application must still handle connection loss, command timeout, duplicate retries, and stale state versions.
- Add heartbeat messages from clients and Host to detect broken connections promptly.
- Do not serialize full internal state and broadcast it to everyone. Build recipient-specific projections.

Example frame payload (the outer TCP frame adds a 4-byte length prefix):

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

### 6.5 Host-authoritative design

The Host runtime is the only authority for:

- Room membership and Host privileges.
- Room settings and phase transitions.
- Ship placement validation and final fleet layouts.
- Turn order and active player.
- Placement and turn deadlines.
- Whether a shot is legal.
- Hit/miss/sunk results.
- Elimination and winner determination.
- Non-host reconnect grace periods and forfeits.
- Final result calculation and broadcast.

Clients send **commands**, not final outcomes. For example, a client sends `game:fire` with a target player ID and coordinate. The Host validates the sender, phase, turn, target, coordinate, and duplicate-shot rules before applying the shot.

The Host is a trusted authority, not a cheat-proof server. Since the Host owns the complete game state and runs on a participant's device, the Host owner can potentially inspect or modify local memory. The MVP is intended for friendly local play, not a tamper-resistant ranked competition.

### 6.6 Information visibility and anti-cheat

- Never send another player's complete fleet layout to an opponent.
- During placement, a player receives their own exact fleet layout and only other players' readiness status.
- During a match, the target player receives impact coordinates for shots against their own board.
- The attacker receives the result of their own shot.
- Other players receive only public match events and aggregate status, not private ship coordinates.
- Eliminated players receive a restricted spectator projection.
- Do not trust client clocks, client turn counters, client hit calculations, client ship counts, or client-provided match status.
- Keep Host-side complete state separate from serialized client view models.
- Avoid logging complete fleet layouts or resume tokens.

### 6.7 Application module boundaries

Suggested feature/service boundaries inside the Flutter project:

- `Profile`: local nickname and avatar.
- `Rooms`: create, discover, join, leave, close, invitation code, room capacity.
- `LanNetworking`: mDNS/Bonjour discovery, TCP listener/client, frame codec, heartbeats, connection lifecycle.
- `Lobby`: room state, Host settings, player list, kick, readiness.
- `Placement`: ship placement commands and validation.
- `Matches`: match lifecycle, turn order, result, history.
- `GameEngine`: pure rules for board, fleet, placement, shot, sinking, elimination, and winner.
- `HostRuntime`: Host orchestration, timer ownership, state store, connection registry, projections.
- `ClientSession`: client connection, command sender, event/state reducer, reconnect.
- `LocalStorage`: settings and optional local match history.
- `Observability`: local diagnostic logs and debug tools (no telemetry upload in MVP).

Keep `GameEngine` independent of Flutter widgets, `dart:io`, Bonjour plugins, and persistence libraries so it can be unit-tested as a pure Dart package.

---

## 7. Data Model and Local State

The following is a logical runtime model, not a server database schema. Active room and match state live in Host memory. No cloud database is used.

### 7.1 Core runtime models

#### Player

- `id` — random ID generated by Host for this room.
- `displayName`
- `avatarId`
- `role` (`HOST` / `PLAYER`)
- `connectionStatus` (`CONNECTED`, `DISCONNECTED`, `LEFT`, `KICKED`)
- `joinedAt`
- `lastHeartbeatAt`
- `resumeTokenHash` — Host-side in-memory hash for the active room only.

#### Room

- `id` — locally generated UUID.
- `inviteCode` — unique while this Host room is active.
- `hostPlayerId`
- `status`
- `maxPlayers`
- `config`
- `createdAt`
- `hostTcpPort`
- `protocolVersion`

#### RoomMember

- `playerId`
- `role` (`HOST` / `PLAYER`)
- `status` (`CONNECTED`, `DISCONNECTED`, `LEFT`, `KICKED`)
- `joinedAt`
- `lastConnectedAt`
- `disconnectedAt`

#### Match

- `id`
- `roomId`
- `status`
- `boardRows`
- `boardColumns`
- `fleetProfile`
- `placementDeadlineMonotonic`
- `turnDeadlineMonotonic`
- `activePlayerId`
- `turnNumber`
- `stateVersion`
- `startedAt`
- `finishedAt`
- `winnerPlayerId`

Use a monotonic time source for in-process deadlines where possible. Do not persist or compare device wall-clock timestamps as the authoritative timer.

#### MatchPlayer

- `playerId`
- `turnOrder`
- `status` (`ALIVE`, `ELIMINATED`, `FORFEITED`, `SPECTATING`)
- `readyAt`
- `eliminatedAt`
- `disconnectDeadlineMonotonic`
- `shotsFired`
- `hits`
- `misses`
- `shipsSunk`
- `timeouts`

#### Ship

- `id`
- `playerId`
- `shipType` or stable ship key
- `length`
- `orientation`
- `startRow`
- `startColumn`
- `isSunk`

#### Shot

- `id`
- `turnNumber`
- `attackerPlayerId`
- `targetPlayerId`
- `row`
- `column`
- `result` (`MISS`, `HIT`, `SHIP_SUNK`)
- `createdAt`
- Unique logical key for `(attackerPlayerId, targetPlayerId, row, column)` if the no-repeat rule is retained.

#### MatchResult

- `matchId`
- `winnerPlayerId`
- `rankings`
- `durationSeconds`
- `playerStatistics`
- `completedAt`

### 7.2 Local persistence

- Persist nickname, avatar, audio settings, tutorial completion, and user preferences locally.
- Optionally persist completed match results on each participant's own device.
- Do not persist an active match in a way that suggests it can survive Host termination. Host exit ends the room by design.
- Do not add a network database or cloud synchronization layer.
- A Host may write a local diagnostic snapshot for crash analysis only if it does not enable clients to restore or continue an old active match.

### 7.3 Data integrity requirements

- Unique room invitation code while the room is active on a given Host.
- A player cannot join the same room more than once under multiple active connections.
- A room cannot exceed its configured capacity.
- A ship placement must pass board bounds, orientation, and overlap checks.
- The configured fleet profile must fit the selected board.
- A match may have only one active player per turn.
- A shot must reference an alive target and an in-range cell.
- A turn transition must increment `turnNumber` and `stateVersion` exactly once.
- A finished match must have at most one winner.
- Once Host closure is committed, no new client commands are accepted.

---

## 8. LAN Message Protocol

### 8.1 General request envelope

Every client command should include a request ID, room ID, protocol version, and expected state version when the command depends on a specific game state.

```json
{
  "protocolVersion": 1,
  "messageType": "placement:ready",
  "requestId": "uuid",
  "roomId": "uuid",
  "playerId": "uuid",
  "expectedStateVersion": 12,
  "payload": {}
}
```

Host acknowledgements should include the same `requestId`, success/error code, and resulting state version. Use request IDs and idempotency tracking so a client retry after a short Wi-Fi interruption does not apply the same command twice.

### 8.2 Client-to-Host commands

| Message | Purpose | Validation |
|---|---|---|
| `room:join` | Join by invitation code | Correct code, supported protocol, room joinable, capacity available. |
| `room:leave` | Leave room | Sender is a room member; apply match leave policy. |
| `room:config:update` | Update room settings | Sender is Host; lobby still configurable; config passes limits. |
| `room:player:kick` | Remove a lobby player | Sender is Host; target is a member; match has not started. |
| `room:start-placement` | Start preparation phase | Sender is Host; minimum player count; valid config. |
| `room:close` | Close room/end match | Sender is Host. |
| `placement:set` | Place or move a ship | Sender owns the board; placement phase active; placement valid. |
| `placement:auto` | Request automatic fleet placement | Sender owns the board; placement phase active. |
| `placement:ready` | Confirm fleet is complete | All ships placed legally. |
| `game:fire` | Fire at target coordinate | Active turn owner; living target; valid cell; no repeated shot. |
| `game:request-snapshot` | Request current authorized state | Sender belongs to room/match and is still admitted. |
| `client:heartbeat` | Report client connection health | Valid active connection. |
| `session:resume` | Reclaim a temporarily disconnected seat | Resume token valid, Host room still active, grace period not expired. |

### 8.3 Host-to-client events

| Event | Purpose |
|---|---|
| `room:joined` | Player ID, room ID, filtered lobby snapshot, resume token. |
| `room:state` | Player list, settings, readiness, phase. |
| `room:player-joined` | New member joined. |
| `room:player-left` | Member left or was removed. |
| `room:config-updated` | New Host settings. |
| `room:closed` | Host explicitly closed room or ended match. |
| `placement:started` | Placement deadline and fleet profile. |
| `placement:state` | Caller-specific placement status. |
| `placement:ready-state` | Public readiness projection. |
| `placement:completed` | Placement phase ended; match is starting. |
| `game:started` | Turn order and initial public match state. |
| `game:turn-started` | Active player and turn deadline/remaining time. |
| `game:shot-result` | Caller-authorized shot result. |
| `game:public-activity` | Limited event for other players. |
| `game:player-eliminated` | Public elimination event. |
| `game:player-disconnected` | Non-host connection status update. |
| `game:player-reconnected` | Non-host reconnection status update. |
| `game:state-snapshot` | Permission-filtered current state. |
| `game:finished` | Winner, ranking, and final statistics. |
| `game:aborted` | Host loss or explicit early termination. |
| `host:heartbeat` | Host liveness signal and current state version. |
| `protocol:error` | Stable error code and safe user-facing message. |

### 8.4 Error codes

Use stable machine-readable codes, such as:

- `ROOM_NOT_FOUND`
- `ROOM_CODE_INVALID`
- `ROOM_FULL`
- `ROOM_ALREADY_STARTED`
- `HOST_ONLY_ACTION`
- `INVALID_ROOM_CONFIG`
- `UNSUPPORTED_PROTOCOL_VERSION`
- `PLACEMENT_PHASE_NOT_ACTIVE`
- `INVALID_SHIP_PLACEMENT`
- `FLEET_INCOMPLETE`
- `NOT_YOUR_TURN`
- `TARGET_NOT_ALIVE`
- `INVALID_TARGET_CELL`
- `CELL_ALREADY_FIRED_AT`
- `MATCH_ALREADY_FINISHED`
- `STATE_VERSION_CONFLICT`
- `SESSION_EXPIRED`
- `HOST_CLOSING_ROOM`
- `LAN_PERMISSION_DENIED`
- `HOST_UNREACHABLE`
- `RATE_LIMITED`

Do not expose stack traces, local filesystem paths, raw exception messages, or private fleet data to clients.

---

## 9. Game Engine and State Transitions

### 9.1 Pure domain rules

Implement and unit-test the following functions independently of Flutter widgets and networking:

- `validateBoardConfig(rows, columns)`
- `validateFleetProfile(profile, rows, columns)`
- `getShipCells(start, orientation, length)`
- `validateShipPlacement(board, ship, candidatePlacement)`
- `autoPlaceFleet(board, fleetProfile, randomSeed?)`
- `resolveShot(targetBoard, row, column)`
- `isShipSunk(ship, hitCells)`
- `isPlayerEliminated(playerFleet, hitCells)`
- `getNextLivingPlayer(turnOrder, currentPlayerId, playerStatuses)`
- `isMatchFinished(playerStatuses)`
- `buildPlayerView(matchState, viewerPlayerId)`

The pure game engine is the most important shared correctness boundary. It must be tested thoroughly before connecting it to TCP.

### 9.2 Match phase transitions

```text
LOBBY
  | Host starts placement
  v
PLACEMENT
  | all ready OR preparation deadline reached
  v
STARTING
  | Host assigns random turn order and initializes deadline
  v
ACTIVE
  | shot -> resolve -> eliminate if necessary -> next living player
  | only one living player remains
  v
FINISHED
```

Terminal paths:

```text
LOBBY or PLACEMENT or ACTIVE
  | Host closes/exits or Host heartbeat is lost
  v
ABORTED_HOST_EXIT / ABORTED_HOST_LOST
```

All phase transitions must be validated and performed by the Host runtime. A client cannot force a phase transition by sending a local timer event.

### 9.3 Shot resolution flow

A shot should be processed atomically within the Host event loop / state coordinator:

1. Resolve the sender's player identity from the active TCP connection; do not trust a client-supplied player ID alone.
2. Confirm the room and match are active.
3. Confirm the sender owns the current turn.
4. Confirm the target is alive and is not the attacker.
5. Validate row and column boundaries.
6. Check whether this attacker has already fired at this target cell.
7. Resolve `MISS`, `HIT`, or `SHIP_SUNK` using Host-owned fleet data.
8. Update statistics and target ship state.
9. Determine whether the target player is eliminated.
10. Determine whether the match has a winner.
11. If the match continues, select the next living player and set a new turn deadline.
12. Increment the state version exactly once for the accepted command.
13. Emit permission-filtered events to the attacker, target, and remaining room members.
14. Return an acknowledgement to the sender.

Serialize state-changing commands through a single coordinator or queue so two commands cannot consume the same turn concurrently.

### 9.4 Timer processing

- Host owns placement and turn timers.
- Use a monotonic elapsed-time source for in-process deadlines; avoid system wall-clock changes affecting gameplay.
- On Host app resume, detect whether a deadline has passed and apply the correct transition immediately.
- Client countdowns are display-only and are periodically corrected by Host events.
- Never accept a `timeRemaining` or client deadline as authoritative.
- If the Host app is backgrounded or suspended, the game may pause unexpectedly. Keep hosting foreground-only in MVP and use a screen-awake mechanism while hosting when appropriate.

### 9.5 Heartbeat and Host-loss detection

- Host sends `host:heartbeat` approximately every 3 seconds.
- Clients track the time since the last valid Host heartbeat using a monotonic timer.
- If no heartbeat is received for approximately 8–10 seconds, mark the room `ABORTED_HOST_LOST`.
- On explicit closure, do not wait for heartbeat timeout: immediately handle `room:closed` / `game:aborted`.
- Do not attempt automatic Host election, transfer, or migration.
- On Host close, stop advertiser, close `ServerSocket`, dispose connections, cancel timers, and clear active in-memory state.

---

## 10. Flutter Application Structure

Suggested feature-first structure:

```text
lib/
  app/
    app.dart
    router.dart
    bootstrap.dart
    theme/
    localization/
  core/
    config/
    errors/
    permissions/
    storage/
    utils/
    widgets/
  features/
    profile/
      data/
      domain/
      presentation/
    home/
      presentation/
    rooms/
      data/
      domain/
      presentation/
    lan_networking/
      data/
      domain/
      services/
        lan_discovery_service.dart
        lan_advertiser_service.dart
        tcp_host_service.dart
        tcp_client_service.dart
        frame_codec.dart
        heartbeat_service.dart
        connection_registry.dart
    lobby/
      data/
      domain/
      presentation/
    placement/
      data/
      domain/
      presentation/
      widgets/
        board_canvas.dart
        ship_placement_layer.dart
    match/
      data/
      domain/
      presentation/
      widgets/
        battle_board_canvas.dart
        target_player_selector.dart
        turn_timer.dart
        shot_effects.dart
    results/
      data/
      domain/
      presentation/
    settings/
      data/
      presentation/
  game_engine/
    board/
    fleet/
    placement/
    combat/
    turns/
    elimination/
    projections/
  host_runtime/
    room_coordinator.dart
    match_state_store.dart
    host_timer_controller.dart
    client_connection_registry.dart
    projection_builder.dart
  shared/
    models/
    protocol/
    widgets/
    animations/
    audio/
  main.dart
```

### 10.1 Client architecture rules

- Separate UI state from Host-owned domain state.
- Use Riverpod providers/notifiers for profile, LAN discovery, room, lobby, placement, match, and connection state.
- Use repositories/interfaces to abstract local storage, LAN discovery, and TCP transport.
- Keep exactly one Host runtime per active Host room.
- Keep one TCP connection per joined client session.
- Register stream/socket listeners once and remove/dispose them predictably.
- Validate incoming payload schemas before changing client state.
- Reconnect a non-host player using the same local player identity and resume token while the room is still active and the grace period remains.
- Do not attempt to reconnect to another elected Host.
- Make animations respond to confirmed Host events, not optimistic local outcomes.
- The Fire button may show a short pending state, but the board must not permanently mark a hit/miss until Host confirms it.

### 10.2 Offline and poor-LAN behavior

- The app must work without Internet access after installation.
- No online-only bootstrap, analytics, fonts, remote configuration, or API call may be required to create/join/play a room.
- If a device has no Internet but LAN is available, show normal LAN functionality.
- If the device is disconnected from Wi-Fi or local-network permission is denied, show a clear connection state and the relevant recovery instructions.
- If the client loses its connection to the Host, allow a reconnect attempt during the non-host grace period.
- If the Host is lost, terminate the local match UI and return to Home with a clear explanation.
- Do not display “reconnecting to server”; use “Reconnecting to Host” or “Host disconnected”.

---

## 11. Platform Permissions and LAN Compatibility

### 11.1 Android

- Declare and request the local-network access permission required by the Android target OS version.
- Flutter's current local-network guidance states that Android 17 (API level 37), for apps targeting that level or higher, blocks LAN access by default unless `ACCESS_LOCAL_NETWORK` is declared and requested at runtime. Test the permission flow on supported Android versions and opt-in test configurations before release.
- Use `permission_handler` (or a verified equivalent) to request `Permission.accessLocalNetwork` before initializing discovery or opening local sockets where the OS requires it.
- Handle denied and permanently denied permission states with an explanation and a route to system settings.
- Add the Bonjour/NSD-related manifest permissions required by the selected discovery package and verify the merged manifest in the release build.

### 11.2 iOS

- Add `NSLocalNetworkUsageDescription` to `ios/Runner/Info.plist` with a user-facing explanation.
- Add the exact `_upfleet._tcp` service type to `NSBonjourServices` if Bonjour discovery/advertising uses it.
- Trigger the local-network permission prompt through a clear user action such as **Find Rooms** or **Create Room**.
- Handle permission denial gracefully and explain how to enable Local Network access in Settings.
- Test on physical iPhones/iPads; simulator behavior is not sufficient for validating Bonjour and Wi-Fi discovery.

### 11.3 Router and Wi-Fi limitations

- The Host and clients must be on the same reachable subnet/LAN.
- Guest Wi-Fi, AP/client isolation, VLAN separation, managed networks, VPNs, or multicast filtering may prevent discovery or direct connections.
- Provide a troubleshooting screen and optional manual IP/port/QR fallback.
- Do not attempt to bypass network isolation with Internet services; explain that the current room requires a LAN that allows device-to-device communication.
- IPv4 should be the first-tested path. Handle IPv6 service addresses correctly if the selected plugin returns them.

### 11.4 Permission and network validation acceptance

- Create and join a room on two physical Android devices on one Wi-Fi network.
- Repeat with Internet disabled on the router/access point.
- Verify first-run permission prompts and denied-permission states.
- Create and join a room on two physical iOS devices.
- Verify mixed Android/iOS sessions on the same Wi-Fi.
- Verify behavior when the devices use guest Wi-Fi or client isolation: show an explanatory failure rather than hanging indefinitely.
- Verify the manual fallback where available.

---

## 12. Security, Fairness, and Abuse Prevention

LAN-only does not mean that every device on the Wi-Fi is trusted. A nearby user may inspect network traffic or send malformed packets. Apply defensive validation even though the game is designed for friendly play.

- Treat the Host as the trusted authority. Document that Host-side cheating cannot be fully prevented in a no-backend, participant-hosted design.
- Generate room codes and session/resume tokens using a cryptographically secure random source.
- Validate room code, protocol version, nickname, room capacity, phase, and payload structure during the join handshake.
- Rate-limit failed room-code attempts per remote connection/IP and close abusive connections.
- Bind client identity to the accepted TCP connection; do not trust player IDs supplied in later commands.
- Enforce all game rules in the Host runtime even if the client UI disables invalid actions.
- Validate message lengths, JSON structure, enum values, coordinates, and allowed command frequency.
- Reject unknown protocol versions and unknown critical message types safely.
- Keep private fleet layouts out of unauthorized client payloads.
- Do not log room resume tokens, private layouts, or full sensitive payloads.
- On room closure, revoke all in-memory resume tokens and reject new commands.
- Consider optional per-session message authentication/encryption only after the basic protocol is correct; do not claim strong confidentiality against a malicious Wi-Fi participant unless transport encryption and key verification are implemented and tested.
- Moderate display names and prevent impersonation of reserved system labels.
- Do not add chat in MVP; this avoids moderation and abuse complexity.

---

## 13. Testing Strategy

### 13.1 Game engine unit tests

Cover at minimum:

- Valid and invalid board dimensions.
- Fleet fit validation on the smallest and largest supported maps.
- Horizontal and vertical ship cell generation.
- Out-of-bounds placement.
- Overlapping ship placement.
- Legal ship adjacency.
- Auto-placement success and bounded retry/failure behavior.
- Hit, miss, repeated shot, and ship sunk cases.
- Player elimination after the final ship cell is hit.
- Turn skipping for eliminated players.
- Winner determination.
- Public/private state projection and information-leak checks.

### 13.2 LAN transport and protocol tests

- Host binds to an available local TCP port and accepts a client.
- Client discovers the Host's Bonjour service on the same LAN.
- Client resolves the service and connects to the returned address/port.
- Join handshake succeeds with the correct room code and fails with an incorrect code.
- Frame codec handles partial reads, multiple frames in one read, malformed JSON, and oversized frames.
- Request IDs correlate acknowledgements correctly.
- Duplicate command retries do not apply a shot twice.
- Heartbeats detect a disconnected client and disconnected Host.
- Host closure stops advertisement and closes all accepted sockets.
- Unsupported protocol versions are rejected with a stable error.

### 13.3 Host-runtime integration tests

- Create room and start local Host runtime.
- Join with a valid code and reject invalid, full, and already-started rooms.
- Enforce Host-only settings changes.
- Kick and leave behavior.
- Start placement with the minimum player count.
- Reject Ready while fleet placement is incomplete.
- Complete placement when everyone is ready.
- Auto-place missing fleets on preparation timeout.
- Resolve shots and update statistics.
- Reject shots from the wrong player or wrong phase.
- Reject duplicate shots and out-of-range coordinates.
- Skip turns after timeout.
- Eliminate a player and determine the final winner.
- Reconnect a non-host player and return the correct private snapshot.
- Verify no player's ship layout leaks to other clients.
- Verify two simultaneous shot commands cannot consume the same turn.
- Explicit Host exit broadcasts termination and closes the room.
- Simulated Host process loss causes clients to detect Host unavailability and abort.
- Verify there is no Host election or migration path.

### 13.4 Flutter tests

- Widget tests for profile, create-room, discover-room, join-room, and validation flows.
- Lobby updates when players join, leave, or become ready.
- Placement interactions: drag/tap, rotate, undo/move, Auto Place, Ready.
- Board hit-testing and coordinate conversion at different screen sizes.
- Timer rendering from Host-provided state.
- Turn and target selection states.
- Shot-pending, confirmed hit/miss, and error states.
- LAN permission prompts, denial, and system-settings recovery guidance.
- Discovery empty state and manual-connection fallback.
- Host-disconnected overlay and immediate return-to-home behavior.
- Accessibility labels and text scaling.

### 13.5 Physical-device multiplayer tests

Use at least 2–6 physical phones/tablets on one Wi-Fi network. Simulators/emulators alone are insufficient for validating LAN discovery, multicast, and OS permission behavior.

Scenarios:

- Two Android devices on the same Wi-Fi.
- Two iOS devices on the same Wi-Fi.
- Mixed Android/iOS devices.
- Same Wi-Fi with Internet disabled.
- Wi-Fi router with guest/client isolation enabled.
- One client temporarily disconnects and reconnects.
- Host explicitly exits during lobby, placement, and an active match.
- Host app is force-closed or the Host phone loses Wi-Fi.
- Client app is backgrounded and resumed.
- Host app is backgrounded and resumed; verify the documented foreground-hosting limitation.
- All players finish a complete match with legal placements and shots.

### 13.6 MVP reliability targets

- Support 2–6 participants in one LAN room.
- Discovery should show an available Host within a few seconds on a compatible Wi-Fi network.
- Normal local command-to-confirmation latency target: under 200 ms on a healthy local network; treat this as a target to measure, not a guarantee.
- No duplicate turn consumption under retries or simultaneous commands.
- A non-host reconnecting within the grace period receives a consistent snapshot.
- Host explicit exit is reflected on connected clients immediately.
- Abrupt Host loss is detected within the configured heartbeat timeout.
- No game functionality requires Internet connectivity.
- No private fleet layout is present in unauthorized client messages.

---

## 14. Local Diagnostics and Operations

There is no server operations stack. Diagnostics are local to the devices.

- Structured local logs with `roomId`, `matchId`, `playerId`, `requestId`, `stateVersion`, and connection role where safe.
- Include a debug-only connection panel showing discovered service, local endpoint, socket status, last heartbeat, protocol version, and state version.
- Provide a one-tap local diagnostics export for bug reports, excluding room secrets, resume tokens, and private fleet layouts.
- Do not upload telemetry or crash reports in MVP unless the product later explicitly adds a consent-based online service.
- No health endpoints, cloud monitoring, TLS termination, database backup, or server deployment checklist is required.

---

## 15. Development Phases and Deliverables

Build in vertical slices. Each phase must produce a working, testable increment rather than only scaffolding.

### Phase 0 — Confirm Rules and Prove Local Networking

**Goal:** Prove that two physical Flutter devices can discover and connect directly over Wi-Fi without Internet or a backend.

Tasks:
- Freeze the approved product constraints: LAN-only, no backend, Host-authoritative, Host exit ends room, no Host migration.
- Confirm private-board-per-player game mode and the initial player/board/fleet/timer presets.
- Create the Flutter project skeleton and feature boundaries.
- Evaluate Bonsoir and `nsd` for mDNS/Bonjour service registration and discovery; choose one after testing on physical Android and iOS devices.
- Open a Dart `ServerSocket` on one device and connect from a second device using `Socket`.
- Send a framed ping/pong message and verify partial-frame handling.
- Test discovery and direct connection with Internet disabled.
- Add a basic permission flow for Android/iOS.
- Write `GAME_RULES.md` and a short LAN protocol specification.

Deliverables:
- Flutter app skeleton.
- A small LAN discovery/TCP proof-of-concept screen.
- `GAME_RULES.md`.
- `LAN_PROTOCOL.md`.
- Architecture decision record for discovery package and TCP framing.

Acceptance criteria:
- Two physical devices on the same compatible Wi-Fi can discover and connect.
- The same test works when Internet access is disabled.
- No NestJS, cloud service, or external server is involved.
- Permission denial is handled with a readable message.

### Phase 1 — Profiles and Local Room Lifecycle

**Goal:** Create a Host room and let other players join by code over LAN.

Tasks:
- Implement local nickname and avatar storage.
- Implement local random room ID and invitation code generation.
- Implement Host TCP listener lifecycle.
- Implement mDNS/Bonjour advertisement with `_upfleet._tcp`.
- Implement client discovery and discovered-room list.
- Implement room-code handshake and Host admission validation.
- Implement player capacity and duplicate-connection protection.
- Implement room list, Host badge, join/leave, kick, and close-room controls.
- Implement manual IP/port or QR fallback if practical and compatible with the privacy model.

Deliverables:
- Create Room and Discover/Join Room flows.
- Local TCP Host/client services.
- Room coordinator and connection registry.
- Room lifecycle tests.

Acceptance criteria:
- 2–6 devices can join one Host room on the same LAN.
- Invalid room codes, full rooms, and unsupported protocol versions are rejected.
- Host can close the lobby and all connected clients return to Home.
- The room cannot be discovered or joined over the Internet.

### Phase 2 — Host Lobby Settings and Synchronization

**Goal:** Provide a fully synchronized lobby and Host-controlled configuration.

Tasks:
- Implement player list and connection status.
- Implement Host settings for board rows/columns, fleet preset, max players, placement timer, and turn timer.
- Validate every setting in the Host runtime.
- Broadcast settings changes and room state versions.
- Implement Host-only actions and client-side disabled states.
- Show room code and share/copy UI.

Deliverables:
- Lobby UI.
- Host configuration UI.
- Room state projection and synchronization.

Acceptance criteria:
- All clients see the same public lobby state.
- Only Host commands can change room configuration.
- Invalid settings are rejected even if a client sends a handcrafted message.

### Phase 3 — Board Renderer and Ship Placement

**Goal:** Make each player able to build a valid private fleet.

Tasks:
- Implement responsive board renderer with `CustomPainter`.
- Implement ship selection, tap/drag placement, rotation, move, and undo.
- Implement placement validation in the pure game engine.
- Implement Auto Place.
- Send placement commands to Host and synchronize readiness state.
- Keep exact fleet placement private to its owner and Host.
- Add clear valid/invalid previews and placement hints.

Deliverables:
- Board canvas and placement interaction.
- Pure placement validator and auto-placement algorithm.
- Placement synchronization messages.

Acceptance criteria:
- Ships cannot overlap or leave the board.
- Every player can place the complete fleet and press Ready.
- Other clients cannot inspect another player's private ship layout.
- Host rejects invalid placement commands even when UI validation is bypassed.

### Phase 4 — Preparation Timer and Match Start

**Goal:** Move the room from placement into a synchronized match.

Tasks:
- Implement Host-owned preparation deadline.
- Implement countdown display on all clients.
- Start immediately when every player is ready.
- Implement random fleet completion on timeout for players who are not ready.
- Implement the minimum-player rule and cancellation path.
- Generate randomized turn order and initial match state.

Deliverables:
- Placement timer controller.
- Match-start state transition.
- Turn-order display.

Acceptance criteria:
- All devices agree when placement ends and the match starts.
- Client clocks cannot force an early or late transition.
- Timeout auto-placement always produces a valid fleet or returns a controlled error.

### Phase 5 — Turn-Based Combat

**Goal:** Complete the main attack loop.

Tasks:
- Implement living-target selection.
- Implement attack history per attacker-target pair.
- Implement one-shot-per-turn rule.
- Implement `game:fire` request/acknowledgement over TCP.
- Validate turn ownership, target, coordinates, and repeated shots in Host runtime.
- Resolve hit/miss/sunk and update state version.
- Build recipient-specific events for attacker, target, and other players.
- Implement turn timer and timeout skip.

Deliverables:
- Combat game engine.
- TCP combat messages.
- Target selection and battle board UI.
- Hit/miss feedback.

Acceptance criteria:
- Only the active player can fire.
- Every accepted shot consumes exactly one turn.
- Duplicate, illegal, or stale shots are rejected without changing match state.
- Attacker and target receive the correct information; other players do not receive private board data.

### Phase 6 — Elimination, Spectating, and Results

**Goal:** End the match correctly and present the winner.

Tasks:
- Detect sunk ships and fully eliminated fleets.
- Mark eliminated players and prevent them from firing.
- Implement next-living-player selection.
- Detect the last remaining player.
- Calculate final ranking and match statistics on Host.
- Build restricted spectator view for eliminated players.
- Broadcast final result to all clients.
- Optionally persist each device's own copy of the match result locally.

Deliverables:
- Elimination and victory engine.
- Final result model.
- Result and spectator UI.
- Optional local match history screen.

Acceptance criteria:
- A match ends exactly when one player remains alive.
- Eliminated players are skipped in all subsequent turns.
- Winner and elimination ranking are identical on all connected clients.

### Phase 7 — Connection Resilience and Host Termination

**Goal:** Handle ordinary client Wi-Fi interruptions and make Host-loss behavior explicit.

Tasks:
- Implement client heartbeat and Host heartbeat.
- Implement non-host reconnect tokens and the 30-second grace period.
- Restore a non-host player with the correct permission-filtered snapshot.
- Implement active-turn disconnect timeout behavior.
- Implement explicit Host-close broadcast.
- Implement abrupt Host-loss detection after the heartbeat timeout.
- Ensure Host close stops advertising, closes sockets, cancels timers, and clears state.
- Add regression tests proving that no Host migration/election is possible.

Deliverables:
- Heartbeat and connection lifecycle services.
- Non-host reconnect flow.
- Host termination flow and UI.
- LAN disconnect test suite.

Acceptance criteria:
- A non-host player can return within the grace period while the Host remains active.
- Explicit Host exit ends the match for all connected clients immediately.
- Abrupt Host loss is detected within the configured timeout.
- Clients never continue an active match or elect a new Host after Host loss.

### Phase 8 — LAN Permissions, Compatibility, and UX Polish

**Goal:** Make LAN onboarding understandable and reliable on supported Android/iOS devices.

Tasks:
- Complete Android local-network permission declaration and runtime request for relevant OS/API targets.
- Complete iOS Local Network usage description and Bonjour service declaration.
- Implement discovery loading, empty, denied, and failed states.
- Add Wi-Fi troubleshooting for guest network/AP isolation/VPN cases.
- Add manual IP/port or QR fallback if supported by the selected package and platform policy.
- Add screen-awake behavior and foreground-hosting warnings.
- Add visual polish, audio, haptics, and reduced-motion behavior.
- Add localization framework and initial language set.

Deliverables:
- Android/iOS permission configuration.
- LAN troubleshooting UX.
- Polished home, lobby, placement, combat, and results screens.
- Accessibility checklist and tests.

Acceptance criteria:
- LAN access permission prompts are clear and correctly handled.
- Compatible Android/iOS devices can discover one another on the same Wi-Fi.
- The app explains why discovery may fail on isolated networks.
- Effects remain responsive on supported mid-range devices.

### Phase 9 — Security, Physical-Device Testing, and Release Candidate

**Goal:** Prepare a stable offline/LAN-only release candidate.

Tasks:
- Review join handshake, room-code generation, session tokens, and rate limiting.
- Audit TCP frame parsing, size limits, malformed payload handling, and protocol versioning.
- Audit every client projection for hidden fleet leaks.
- Run full 2–6 device matches on Android, iOS, and mixed devices.
- Test Internet-disabled play.
- Test Host exit, Host crash, Host Wi-Fi loss, client disconnect, and client reconnect.
- Profile CPU, memory, battery, and rendering on mid-range phones.
- Prepare Android and iOS release builds and store privacy disclosures for local-network access.

Deliverables:
- Security and protocol review report.
- Physical-device test report.
- Performance report.
- Release candidate builds and store submission checklist.

Acceptance criteria:
- No known path allows a client to alter shot results, turn order, ship placement, or winner state.
- No private fleet layout is sent to unauthorized clients.
- A complete match works without Internet access on a compatible LAN.
- Host exit behavior is consistent across all clients.
- No backend, cloud database, or external signaling service is required.

### Phase 10 — Post-MVP Enhancements

Only begin after the core LAN multiplayer loop is stable.

Potential features:

- Offline practice mode against AI opponents.
- Additional board themes and ship skins (cosmetic only).
- Custom fleet editor and more room rules.
- Alternate game modes, including a shared-map variant.
- Advanced local replay viewer.
- Local tournament brackets managed by the Host.
- Nearby-device quick join without typing a room code (optional; keep room admission controlled).
- Bluetooth/local hotspot exploration only if product research demonstrates a real need; it is not part of the approved Wi-Fi MVP.

Do not add Internet multiplayer or Host migration unless the product scope is explicitly changed in a future plan revision.

---

## 16. Definition of Done

A feature is complete only when:

1. Its acceptance criteria pass.
2. The pure game rules are unit-tested.
3. Host-side validation exists for every important game rule.
4. Relevant TCP/protocol, Host-runtime, widget, and physical-device tests are added.
5. Events and DTOs are documented and version-compatible.
6. No unauthorized player can read or mutate private game state.
7. Logs provide enough context to diagnose failures without exposing room secrets or hidden fleet data.
8. UI states are usable on supported phone sizes.
9. Multiplayer behavior has been tested with at least two physical devices on the same Wi-Fi.
10. Features do not introduce a mandatory Internet or backend dependency.
11. Host termination follows the approved policy and never attempts migration.

---

## 17. Key Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Router blocks device-to-device traffic | Players cannot connect despite using the same Wi-Fi name | Detect timeout, show troubleshooting, support manual endpoint fallback where possible. |
| mDNS/Bonjour discovery is filtered | Host does not appear in room list | Test physical devices, show scan diagnostics, provide manual IP/QR fallback. |
| Local-network permission is denied | Socket/discovery operations fail | Request permission at the correct point; explain how to enable it in system settings. |
| Host app is killed or background-suspended | Entire room/match ends | Foreground-only hosting, screen-awake support, clear warning, Host-loss heartbeat. |
| Host can inspect hidden fleets | Host can cheat | Document the trust model; keep the MVP for friendly play, not competitive ranked play. |
| Client sends malformed or hostile frames | Crash, memory exhaustion, or invalid game state | Frame size limits, strict schema validation, rate limits, safe error handling. |
| Client and Host disagree about turns | Invalid or duplicated shots | Host-authoritative state, state versions, request IDs, serialized commands. |
| Client disconnect stalls a match | Match becomes slow | Short reconnect grace period and turn-timeout/skip policy. |
| Placement timeout creates invalid layouts | Match cannot start | Reuse pure placement validator and bounded auto-placement algorithm. |
| Mobile OS changes timer behavior in background | Timer becomes inaccurate or host pauses | Host remains foreground-only; detect lifecycle transitions and show warnings. |
| Host loss destroys active match | Players lose progress | This is an accepted product rule; notify all clients and save only completed results locally. |
| Scope drifts into Internet multiplayer | Additional infrastructure and complexity | Keep Internet matchmaking, signaling, relay, and cloud persistence explicitly out of MVP. |

---

## 18. Recommended Initial Configuration

Use this as the first playable build configuration:

```yaml
network:
  mode: LAN_ONLY
  transport: TCP
  discovery: MDNS_BONJOUR
  serviceType: _upfleet._tcp
  topology: HOST_STAR
  internetRequired: false
  backendRequired: false
  hostMigration: false
  hostExitEndsRoom: true
  hostHeartbeatIntervalSeconds: 3
  hostLostTimeoutSeconds: 10
players:
  minimum: 2
  recommendedMaximum: 6
room:
  invitationCodeLength: 6
  allowJoinAfterPlacementStarts: false
  hostForegroundRequired: true
board:
  rows: 10
  columns: 10
  minimumRows: 8
  minimumColumns: 8
  maximumRows: 14
  maximumColumns: 14
fleet:
  preset: STANDARD
  shipLengths: [4, 3, 3, 2, 2]
placement:
  durationSeconds: 120
  allowShipAdjacency: true
  allowOverlap: false
  autoPlaceOnTimeout: true
combat:
  turnDurationSeconds: 30
  shotsPerTurn: 1
  extraShotOnHit: false
  targetMode: ANY_LIVING_OPPONENT
  repeatedShotOnSameCellPerAttackerTarget: false
reconnection:
  nonHostGracePeriodSeconds: 30
  hostReconnectSupported: false
persistence:
  activeMatch: HOST_MEMORY_ONLY
  matchHistory: OPTIONAL_LOCAL_ONLY
  cloudSync: false
```

Validate all Host settings and client-provided values in the Host runtime. These values are defaults, not client-trusted constants.

---

## 19. Decisions Already Confirmed

The following decisions are approved and must not be reopened during implementation without an explicit product change:

1. **Network scope:** Same Wi-Fi/LAN only. No Internet multiplayer.
2. **Backend:** No separate backend, no cloud service, no hosted database, no signaling server.
3. **Room authority:** The room creator's device is Host and runs the game authority.
4. **Topology:** Clients connect directly to Host in a star topology.
5. **Host exit:** Host exit or Host unavailability ends the room/match.
6. **Host migration:** Not supported.
7. **Game mode:** Private board per player; active player selects a living opponent and a target coordinate.

The recommended MVP values (2–6 players, 10×10 board, Standard Fleet, 120-second placement, 30-second turn) are implementation defaults. They can be adjusted before the first complete match is built.

---

## 20. Official References

Verify exact package versions and platform behavior again when implementation begins.

### Flutter and Dart networking

- Flutter — Request local network permissions on Android: https://docs.flutter.dev/platform-integration/android/local-network-permission
- Dart — `Socket`: https://api.dart.dev/dart-io/Socket-class.html
- Dart — `ServerSocket`: https://api.dart.dev/dart-io/ServerSocket-class.html
- Flutter — Networking cookbook: https://docs.flutter.dev/cookbook/networking

### LAN discovery

- Bonsoir Flutter package (mDNS / Bonjour / Android NSD): https://pub.dev/packages/bonsoir
- Bonsoir repository: https://github.com/Skyost/Bonsoir
- `nsd` Flutter package (alternative service discovery implementation): https://pub.dev/packages/nsd

### Android and Apple local-network privacy

- Android Developers — Local network permission: https://developer.android.com/privacy-and-security/local-network-permission
- Apple Developer — `NSLocalNetworkUsageDescription`: https://developer.apple.com/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription
- Apple Developer — Understanding local network privacy: https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy

### Flutter permissions and local storage

- `permission_handler`: https://pub.dev/packages/permission_handler
- `shared_preferences`: https://pub.dev/packages/shared_preferences
- `drift` (optional local SQLite history): https://pub.dev/packages/drift

---

## Final Recommendation

Build UpFleet Arena as a **LAN-only, Host-authoritative, turn-based Battleship-style free-for-all**. The Host phone runs the room coordinator, complete game state, timers, validation, and TCP listener inside the Flutter app. Other phones discover the Host through mDNS/Bonjour and connect directly over the same local Wi-Fi network. Use Dart `ServerSocket`/`Socket` for the transport and a tested LAN discovery package such as Bonsoir.

Do not create a NestJS backend, cloud API, database server, Internet signaling system, or host-migration mechanism. Internet access must not be required for room discovery or gameplay. If the Host explicitly exits or becomes unreachable, the room and match end for everyone. Start with 2–6 players, a 10×10 board, a five-ship Standard Fleet, a 120-second placement phase, and a 30-second turn timer. Prioritize the physical-device LAN proof of concept before investing in game polish; router isolation and OS local-network permissions are the largest early technical risks.
