# Architecture

## Components

### LocalFence.app

The UIKit app runs as mobile. It displays the active interface, local and
gateway addresses, discovered IPv4 neighbors, and current block state. It has
no direct raw-packet privilege. It enriches the daemon inventory with an
offline OUI lookup and short-lived Bonjour discovery. Identity results include
a confidence level and remain best-effort.

### localfenced

The launch daemon runs as root and owns route and neighbor discovery,
private-subnet validation, BPF attachment to en0, the bounded in-memory block
table, periodic ARP updates, and corrective updates during restore.

Block state is deliberately not persisted. A daemon restart returns to a safe
unblocked state. The daemon accepts at most 255 entries and enforces an
aggregate send-event ceiling across their selected intervals.

### localfencectl

The root-only CLI uses the same JSON protocol as the app. It is useful for
automation and diagnostics without expanding the daemon command surface.

## Flow

    LocalFence.app (mobile) -- authenticated Unix socket --> localfenced (root)
              ^                                                   |
              | scan/status JSON                                  +- route + ARP
              +---------------------------------------------------+- /dev/bpfN

## Discovery

The daemon reads the default route, validates that the active interface is
en0, and obtains the interface IPv4 address, netmask, and MAC with getifaddrs.
It sends one non-blocking UDP probe per usable address to trigger normal
neighbor resolution, then reads the ARP table.

Active discovery is rejected for subnets larger than /22 or smaller than /30.

## Blocking and restoration

For a selected client, the daemon rechecks that the supplied MAC matches the
current neighbor table. It then periodically advertises the gateway IPv4
address using the iPhone's Wi-Fi MAC directly to that client. Both ARP request
and reply forms are emitted for compatibility.

IP forwarding is not enabled. Traffic the client directs to the iPhone is
therefore dropped.

When a block stops, LocalFence sends repeated corrective ARP replies containing
the real gateway MAC. This reduces recovery time compared with waiting for the
client's neighbor cache to expire.

## Threat model

The daemon assumes a jailbroken device whose root user controls package files.
It protects against an unrelated process running as mobile connecting to the
privileged API. It does not attempt to defend against root, kernel compromise,
or replacement of files under the jailbreak prefix.
