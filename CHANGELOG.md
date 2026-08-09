# Changelog

## 0.2.1

- Use Havoc's valid `Applications` package section.
- Rebuild the rootless release package with synchronized app and daemon
  version metadata.

## 0.2.0

- Add offline OUI vendor lookup for MA-L, MA-M, and MA-S assignments.
- Add Bonjour-based device names and confidence-labeled platform guesses.
- Identify private or randomized MAC addresses without misleading OUI results.
- Add 5, 10, 20, and 50 ms advanced interval options with a global traffic
  ceiling.
- Raise the selected-device limit to 255.
- Adopt the GNU General Public License v3.0 or later.
- Add privacy, legal, and third-party notice documents for public distribution.

## 0.1.1

- Add a complete LocalFence app icon set.
- Request iOS Local Network and Location permissions on first authorized use.
- Move app-daemon IPC to a mobile-accessible authenticated socket.
- Add the rootless app entitlements required for daemon communication.
- Run route and ARP tools directly so discovery works from launchd without a
  rootful shell path.
- Clean up both legacy and current sockets during package lifecycle events.

## 0.1.0

- Initial rootless release.
