# Phase 8 — Physical Device Test Procedure

> The code side of Phase 8 is complete: Android and iOS local-network
> declarations are in place, runtime permission handling is wired into the
> discovery flow, denied and empty discovery states are surfaced, manual IP/port
> fallback remains available, and the Host foreground warning is shown in the
> Create Room flow. The Host also holds a screen wakelock while hosting
> (§4.3), shot/result sound effects and haptics respect independent toggles
> (§5.3), reduced motion shortens animations (§5.2), the UI is localized to
> English and Vietnamese with a language selector, and boards/avatars expose
> screen-reader labels (see `docs/ACCESSIBILITY.md`).
>
> The acceptance criteria of PLAN.md §15 Phase 8 need **2 physical devices on
> one Wi-Fi network**, plus permission prompts on first run. This file is the
> checklist for that run. It has not been executed yet.

---

## 0. Prerequisites

- 2 physical phones (Android + iOS if possible) on the same Wi-Fi.
- Fresh install on at least one device so the permission prompt appears.
- The app installed on each device.

---

## 1. Permission prompts

| # | Step | Expected result |
|---|---|---|
| 1.1 | Open Join Room and tap Scan on first run | The OS asks for local network access |
| 1.2 | Grant permission | Scanning starts and nearby rooms appear |
| 1.3 | Deny permission, then tap Scan again | A readable message explains that local network access is needed; troubleshooting steps are shown |
| 1.4 | Permanently deny, then tap Scan | A message points to system settings; the manual connection remains usable |
| 1.5 | iOS first run | The system prompt appears only when Scan is tapped, never at app launch |

---

## 2. Discovery states

| # | Step | Expected result |
|---|---|---|
| 2.1 | Scan on a network with a Host | Rooms appear within a few seconds |
| 2.2 | Scan on a network with no Host | "No rooms found yet" plus troubleshooting steps |
| 2.3 | Scan on guest Wi-Fi / client isolation | No hang; troubleshooting steps explain the limitation |
| 2.4 | Scan with a VPN active | Failure is explained; manual connection is offered |

---

## 3. Manual fallback

| # | Step | Expected result |
|---|---|---|
| 3.1 | Use manual IP/port with a valid Host endpoint | The client joins the room |
| 3.2 | Use an invalid IP or port | A readable connection error is shown |
| 3.3 | Use manual connection when discovery is blocked | Join succeeds without mDNS |

---

## 4. Host foreground and screen awake

| # | Step | Expected result |
|---|---|---|
| 4.1 | Create a room | The "keep in foreground" warning is visible |
| 4.2 | Background the Host app during a match | Clients eventually report Host loss (or the Host returns and continues, depending on OS suspension) |
| 4.3 | Keep the Host in the foreground | The screen stays awake for the duration of hosting |

---

## 5. Accessibility and polish

| # | Step | Expected result |
|---|---|---|
| 5.1 | Enable large text in system settings | Layouts remain readable |
| 5.2 | Enable reduced motion | Animations shorten or disable |
| 5.3 | Toggle sound and haptics | Settings are respected independently |
| 5.4 | Play on a smaller phone | Boards remain tappable; no overflow |

---

## 6. Regression checks

| # | Step | Expected result |
|---|---|---|
| 6.1 | Repeat Phase 7 reconnect and Host-loss flows | Still pass |
| 6.2 | Disable Internet on the router | Permission and discovery flows still work |
| 6.3 | Mixed Android/iOS session | Discovery and direct connection both work |
