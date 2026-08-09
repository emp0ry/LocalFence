# Privacy Policy

Effective date: August 9, 2026

LocalFence is a self-hosted, open-source application. It has no developer-run
server, user account system, advertising SDK, analytics SDK, or telemetry.

## Information processed on the device

To provide its features, LocalFence processes information visible on the local
network you choose to administer:

- local IPv4 addresses and MAC addresses;
- the active interface, subnet, and gateway addresses;
- Bonjour names, hostnames, and advertised service types;
- organization names from the bundled offline OUI database;
- the selected device, interval, and current in-memory operation state.

This information remains on the iPhone. LocalFence does not upload it to the
developer or to a cloud service.

## Permissions

Local Network permission allows Bonjour discovery on the current LAN.

Location When In Use permission is requested because iOS protects certain
Wi-Fi-related information behind location authorization. LocalFence does not
start location updates, request GPS coordinates, store coordinates, or transmit
location data.

## Network activity

LocalFence sends LAN-local discovery probes, Bonjour queries, and the ARP
management frames explicitly requested by the user. The packaged app does not
contact an analytics or application backend. Updating the OUI database is a
developer/build-time action performed by `scripts/update-oui.py`, not an
automatic app request.

## Storage and retention

The app stores its authorized-use acknowledgement and selected interval in
iOS preferences. The daemon keeps active device state in memory and clears it
when the daemon restarts. Discovered device inventory and Bonjour evidence are
not designed as a persistent history.

Uninstalling the package removes the application and daemon. iOS permission
choices can be changed in Settings. Some jailbreak package managers may retain
ordinary preference files unless they are removed separately.

## Third parties

The offline OUI data associates globally assigned MAC prefixes with registered
organizations. It does not identify a person. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for its source and license.

## Security notice

A jailbroken device has a different security model from stock iOS. Other
privileged software installed by the device owner may be able to inspect local
data or network traffic outside LocalFence's control.

## Contact

Questions about this policy may be sent to `emp0rynew@gmail.com`.
