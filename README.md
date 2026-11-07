# UpFleet Arena

LAN-only, turn-based naval combat game for mobile (Flutter/Dart). One phone acts as the Host (room authority); other players join over the local Wi-Fi network. No backend, cloud service, or Internet dependency.

## Overview

- **Mode:** Private-room, free-for-all Battleship-style naval combat.
- **Players:** 2–6 (structures flexible up to 8).
- **Network:** Same Wi-Fi / LAN only; mDNS/Bonjour discovery + direct TCP sockets.
- **Authority:** The room creator's phone runs the entire game authority in-process.
- **Persistence:** Local preferences and match history only; active match lives in Host memory.

See [PLAN.md](PLAN.md) for the full product/technical plan, [GAME_RULES.md](GAME_RULES.md) for frozen game rules, [LAN_PROTOCOL.md](LAN_PROTOCOL.md) for the wire protocol, and [SECURITY_REVIEW.md](SECURITY_REVIEW.md) for the security posture.

## Project Structure

```
UpFleetArena/
├── PLAN.md, GAME_RULES.md, LAN_PROTOCOL.md, SECURITY_REVIEW.md
├── PHASE*_DEVICE_TEST.md   # Per-phase device test checklists
├── docs/adr/                # Architecture decision records
└── upfleet_arena/           # Flutter application
    ├── lib/
    │   ├── app/             # App shell, router, theme
    │   ├── core/            # Config, providers, storage, permissions
    │   ├── features/        # UI features (home, rooms, lobby, placement, match, profile, lan_lab, lan_networking)
    │   ├── game_engine/     # Board, fleet, placement, combat
    │   ├── host_runtime/    # Host authority: room state, coordinator, projections
    │   └── shared/          # Models, protocol, widgets
    └── test/                # Unit/widget tests
```

## Prerequisites

- Flutter SDK with Dart `^3.13.7`
- Android Studio / Xcode for mobile targets
- Devices on the same Wi-Fi/LAN (client/AP isolation disabled)

## Getting Started

```bash
cd upfleet_arena
flutter pub get
flutter run
```

## Testing

```bash
cd upfleet_arena
flutter analyze
flutter test
```

## Networking Notes

- Room discovery uses mDNS/Bonjour; gameplay uses length-prefixed TCP frames (max 64 KiB).
- Invitation codes are 6 characters (ambiguous `0/O/1/I` excluded) and travel only inside the TCP handshake, never in discovery metadata.
- Host exit terminates the room for everyone (no host migration).

## Documentation

- [PLAN.md](PLAN.md) — product & technical plan
- [GAME_RULES.md](GAME_RULES.md) — frozen game rules
- [LAN_PROTOCOL.md](LAN_PROTOCOL.md) — protocol specification
- [SECURITY_REVIEW.md](SECURITY_REVIEW.md) — security review
- [docs/adr](docs/adr) — architecture decisions
- [upfleet_arena/README.md](upfleet_arena/README.md) — Flutter starter notes
