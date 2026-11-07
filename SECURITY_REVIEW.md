# Security Review — UpFleet Arena MVP

## Scope
LAN-only, Host-authoritative Flutter app. No backend, cloud service or Internet
dependency. Active state lives in Host memory only.

## Controls in place
- Room codes are generated locally from a 6-character unambiguous alphabet.
- Resume tokens are shown once; only their SHA-256 hash is stored on the Host.
- Client identity is bound to the accepted TCP connection; client-supplied
  player IDs are not trusted.
- All game rules are enforced in the Host runtime, including turn ownership,
  target validity, coordinate bounds and duplicate shots.
- State-changing commands are serialized through the Host coordinator.
- Recipient-specific projections prevent hidden fleet layouts and private
  coordinates from reaching other clients.
- TCP frames are length-prefixed, size-limited (64 KiB) and validated as JSON.
- Oversized, malformed or non-object payloads are rejected with stable error
  codes.
- Failed room-code attempts are rate-limited per connection.
- Host close stops advertising, closes sockets, cancels timers and clears state.
- No Host migration or election is implemented or possible.

## Residual risks
- The Host is a trusted participant and can inspect its own memory.
- A malicious LAN participant can attempt protocol abuse; defensive validation
  mitigates but cannot guarantee confidentiality without transport encryption.
- Background suspension of the Host can cause a Host-loss event.

## Conclusion
The MVP meets the approved LAN-only, no-backend, Host-authoritative security
posture. No cloud or Internet dependency is present.
