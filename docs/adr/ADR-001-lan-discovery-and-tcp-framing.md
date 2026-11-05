# ADR-001 — LAN discovery backend and TCP framing

- **Status:** Partially accepted — framing accepted, discovery backend provisional
- **Date:** 2026-11-05
- **Phase:** 0 (PLAN.md §15, Phase 0)
- **Affects:** `lib/features/lan_networking/**`, `lib/shared/protocol/**`

---

## Context

UpFleet Arena is a LAN-only, host-authoritative, turn-based Battleship-style
game. There is no backend, no signalling server, no cloud database and no
Internet dependency (PLAN.md §1.2, §19).

Phase 0 must prove — on real physical devices — that two phones can:

1. discover each other over mDNS/Bonjour on the same Wi-Fi, and
2. exchange framed messages over a direct TCP connection,

with the router's Internet connection disabled.

Two technical choices had to be settled before that proof is possible:

- **Which mDNS/Bonjour package** implements discovery and advertisement.
- **What the TCP framing format** looks like, so that partial reads and
  multiple messages per read are handled correctly.

PLAN.md §6.4 and §8 constrain the framing choice but do not pick a discovery
package; PLAN.md §15 explicitly requires evaluating *both* `bonsoir` and `nsd`
on physical Android and iOS devices before choosing one.

---

## Decision 1 — TCP framing: length-prefixed JSON (accepted)

**The wire format is a 4-byte unsigned big-endian length prefix followed by a
UTF-8 JSON object payload. The maximum accepted inbound payload is 64 KiB.**

```text
+---------------------------+-----------------------------+
| uint32 big-endian length  | UTF-8 JSON payload          |
| 4 bytes                   | `length` bytes              |
+---------------------------+-----------------------------+
```

### Rationale

- **Explicit framing is mandatory.** TCP is a byte stream. A naive
  "one read = one message" implementation corrupts messages as soon as the
  payload spans a segment boundary. PLAN.md §6.4 forbids that assumption.
- **Length prefix over a delimiter.** A delimiter-based format (newline, NUL)
  breaks on JSON payloads that may legitimately contain the delimiter, and
  requires scanning for a terminator inside a possibly hostile payload.
- **JSON over a binary format.** The traffic is low-rate control traffic, not
  media. JSON keeps the protocol inspectable with standard tooling, which
  matters a lot for a LAN game where participants can sniff their own traffic.
  The 64 KiB cap removes the memory-exhaustion vector that raw JSON would
  otherwise open.
- **4 bytes, big-endian.** The header is trivial to implement and to verify by
  eye in a packet capture.

### Consequences

- The receiver must keep a buffer and emit a message only once the declared
  length has fully arrived. This is implemented in `FrameDecoder`.
- A frame declaring more than 64 KiB is rejected with `FRAME_TOO_LARGE` and
  the connection is closed. A payload that is not valid UTF-8, not valid JSON,
  or not a JSON object is rejected with `MALFORMED_PAYLOAD` / `MALFORMED_FRAME`.
- The Host never broadcasts one serialized internal state to everyone; it
  builds recipient-specific projections (PLAN.md §6.6).

### Verification status

| Check | Where | Result |
|---|---|---|
| Byte-by-byte reassembly of one frame | `frame_codec_test.dart` | pass |
| Two frames in one chunk | `frame_codec_test.dart` | pass |
| Split inside the length prefix | `frame_codec_test.dart` | pass |
| Oversized declared length rejected | `frame_codec_test.dart` | pass |
| Malformed JSON rejected | `frame_codec_test.dart` | pass |
| Non-object JSON rejected | `frame_codec_test.dart` | pass |
| Invalid UTF-8 rejected | `frame_codec_test.dart` | pass |
| Buffer consistency over 25 mixed chunks | `frame_codec_test.dart` | pass |
| Same behaviour over a real TCP socket | LAN Lab → *Split frame* | **requires physical devices** |

---

## Decision 2 — Discovery backend: both wired, Bonsoir is the provisional default (provisional)

**Both `bonsoir` (7.1.5) and `nsd` (5.0.1) are implemented behind the
`LanDiscoveryService` / `LanAdvertiserService` interfaces. The LAN Lab lets a
tester switch between them at runtime. `bonsoir` is the provisional default
until the physical-device matrix below is completed.**

### Rationale for keeping both

- PLAN.md §15 requires the choice to be made *after* testing on physical
  Android and iOS devices. Shipping only one package would remove the ability
  to compare them during that test.
- The two packages have materially different native implementations:
  `bonsoir` uses its own Bonjour implementation on iOS/macOS and Android NSD
  on Android; `nsd` is a thinner wrapper over the platform `NetworkService` /
  `NsdManager` APIs. Their behaviour under router filtering, AP isolation and
  permission denial differs in ways only a real device can show.
- The abstraction cost is low: discovery is a narrow interface
  (`start` / `stop` / `rooms` stream / `diagnostics` stream) and the rest of the
  app never references the package.

### Known differences observed in the source

| Aspect | `bonsoir` 7.1.5 | `nsd` 5.0.1 |
|---|---|---|
| Android implementation | Own Bonjour stack + multicast lock | Platform `NsdManager` |
| iOS implementation | Own `BonjourService` / `NetService` wrapper | `NetServiceBrowser` / `NetService` |
| Service type normalization | RFC 6335 normalization applied | Raw type passed through |
| TXT records | `Map<String, String>` | `Map<String, Uint8List?>` (raw bytes) |
| Resolution | `found` then `resolved` events | `autoResolve` with `IpLookupType.any` |
| Error reporting | Typed broadcast/discovery events | `NsdError` with `ErrorCause` |
| Android build health | Builds clean | `nsd_android` still applies the Kotlin Gradle Plugin; Flutter warns that **future Flutter versions will fail to build** until the plugin migrates to built-in Kotlin |

`bonsoir` normalizes the service type and attributes automatically, which
removes a class of "works on one platform only" bugs. `nsd` gives finer control
over IP lookup and returns richer error causes.

The `nsd_android` Kotlin Gradle Plugin warning is not cosmetic: it means the
`nsd` backend is a build-time liability on future Flutter releases, and it
counts against `nsd` in the decision below unless the plugin migrates first.

### The decision procedure (must be run on physical devices)

> This step could not be completed during Phase 0 authoring: no physical
> Android or iOS device was attached to the build machine. **The discovery
> backend choice remains open until the matrix below is filled in.**

Procedure:

1. Put two physical devices on the same Wi-Fi and install the debug build of
   the LAN Lab on both.
2. On device A: **Start hosting**. On device B: **Scan for rooms** with the
   Bonsoir backend, then repeat with the NSD backend.
3. Record, for each backend: whether the room appears, how long it takes, and
   whether the resolved address is usable.
4. Connect and run **Ping**, **Split frame**, **Oversized** and **Malformed**
   from device B. The Host must answer the ping, decode the split frame as one
   message, and answer the two invalid frames with `FRAME_TOO_LARGE` and
   `MALFORMED_FRAME`.
5. Disable Internet on the router/access point and repeat steps 2–4.
6. Enable guest Wi-Fi / AP-client isolation and repeat step 2. Discovery is
   expected to fail; the app must show the troubleshooting text, not hang.
7. Deny the local-network permission on one device and confirm a readable
   message and a route to system settings.
8. Repeat the whole matrix on a mixed Android + iOS pair.

Decision rule: pick the backend that discovers reliably on **both** platforms,
including under AP isolation; if both qualify, pick the one with the simpler
and better-documented error reporting. If neither qualifies, keep the
abstraction and implement a third backend rather than weakening the manual
IP/port fallback.

### Consequences

- `lib/features/lan_networking/domain/lan_discovery.dart` owns the contract.
- The backend is selected at runtime in the LAN Lab, so the final choice is a
  one-line change in `lib/features/lan_lab/domain/lan_lab_controller.dart`
  plus deleting the losing implementation.
- Both packages stay in `pubspec.yaml` until the choice is made, which means
  both native codebases ship in the app. Removing the loser is a required
  cleanup task before the Phase 9 release candidate.

---

## Decision 3 — Discovery metadata never carries the invitation code (accepted)

The advertised service name is a **non-secret** room label or Host nickname.
The invitation code is validated only by the selected Host during the TCP
handshake, and never appears in the service type, the instance name or any TXT
attribute.

**Rationale:** every device on the LAN can inspect mDNS announcements. A code
embedded in the advertisement would be readable by any device on the network,
which defeats the purpose of the code.

---

## Decision 4 — Ephemeral port by default (accepted)

The Host binds port `0` and publishes the effective port in the discovery
record, instead of hard-coding a port.

**Rationale:** hard-coded ports collide with other apps and with a second Host
instance on the same device. The manual IP/port fallback displays the port from
the Host screen, so the user always has the value they need.

---

## Decision 5 — Android toolchain pinned to API 37 (accepted)

**The Android build uses AGP 9.5.0, Gradle 9.6.0 and `compileSdk = 37`, while
`targetSdk` stays at 36.**

### Rationale

`android.permission.ACCESS_LOCAL_NETWORK` does not exist in the API 35 or 36
`android.jar`, so `permission_handler_android` 14.x — the first version that
maps the local-network permission group — cannot compile against API 36.
Compiling against API 37 also lets the app declare the permission it will need
when the target SDK eventually moves to API 37 (PLAN.md §11.1).

The **target** SDK deliberately stays at 36: the runtime permission is only
*enforced* for apps that target API 37, so today's build keeps LAN access
working without an extra prompt, and the manifest declaration is already in
place for the future target bump.

### Consequences

- AGP was bumped from 9.1.0 to 9.5.0 and the Gradle wrapper from 9.3.1 to
  9.6.0, because AGP 9.1.0 cannot resolve the `android-37.0` platform hash and
  AGP 9.5.0 requires Gradle ≥ 9.6.0.
- The build machine needs the Android 17 platform installed. It is pulled
  automatically by the Gradle SDK downloader on the first build.
- The runtime request of `ACCESS_LOCAL_NETWORK` becomes meaningful only when
  `targetSdk` is raised to 37; that change belongs to Phase 8
  (*LAN Permissions, Compatibility, and UX Polish*).

---

## Consequences summary

- The protocol layer has no dependency on the discovery package, so Decision 2
  can change without touching framing, the envelope or the message catalogue.
- `protocolVersion` is `1`. Bump it whenever a change is not backward
  compatible; the Host rejects a mismatching version with
  `UNSUPPORTED_PROTOCOL_VERSION`.
- Phase 0 deliberately ships **no** room, lobby or game logic. The LAN Lab is a
  transport harness, not a prototype of the real client session.

---

## Follow-ups

| # | Task | Owner | Phase |
|---|---|---|---|
| 1 | Run the physical-device discovery matrix and record the results | Product + mobile | Phase 0 (blocking Phase 1) |
| 2 | Remove the losing discovery package and its native code | Mobile | Phase 1 |
| 3 | Add the real `room:join` handshake to replace the `client:ping` probe | Mobile | Phase 1 |
| 4 | Add per-connection rate limiting for failed join attempts | Mobile | Phase 9 |
| 5 | Add the IPv6 link-local address handling check | Mobile | Phase 8 |
