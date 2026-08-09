# Security policy

## Intended boundary

LocalFence is an authorized private-LAN administration tool. It rejects public
IPv4 targets, clients outside the active subnet, the router, the local iPhone,
network and broadcast addresses, multicast MACs, intervals below 5 ms, more
than 255 simultaneous clients, and configurations above the aggregate
send-event ceiling.

It does not provide forwarding, interception, decryption, packet capture,
credential handling, remote administration, persistence of block state across
daemon restarts, or an arbitrary command runner.

## Privilege separation

The app runs as mobile. Raw packet work is isolated in localfenced, which runs
as root under launchd. Requests use a Unix-domain socket owned by mobile, mode
0600.

Socket permissions are not the only authorization check. The daemon reads the
peer UID and PID from the kernel and validates the peer executable path:

- UID mobile must be the installed LocalFence.app/LocalFence.
- UID root must be the installed /usr/bin/localfencectl.

The protocol exposes only status, scan, block, unblock, and stop.

## Reporting

Do not open a public issue for a vulnerability that could put users at risk.
Send a private GitHub security advisory with the affected version, reproduction
conditions, expected and actual behavior, and suggested mitigation if known.

## Operational advice

- Stop all blocks before uninstalling; the package also requests this in its
  removal script.
- Do not lower the source-enforced 5 ms minimum or remove the aggregate traffic
  ceiling without a documented safety review.
- Do not expose the daemon socket through TCP or another network transport.
- Do not add traffic forwarding or capture to the privileged daemon.
