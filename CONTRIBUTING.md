# Contributing

Contributions are welcome when they preserve LocalFence's private-LAN,
authorized-use boundary.

## Development

1. Use a current Theos checkout and full Xcode on macOS.
2. Keep portable parsing and packet construction in Shared/LFCore.
3. Keep all privileged operations in the daemon.
4. Add no arbitrary shell-command IPC.
5. Update the protocol and architecture documents with behavioral changes.
6. Run scripts/test.sh and build a rootless package before a pull request.
7. Ensure new code and data can be distributed under GPL-3.0-or-later or a
   compatible license, and add required third-party notices.

Features for stealth, credential interception, traffic capture, public-IP
targeting, or bypassing network defenses are out of scope.
