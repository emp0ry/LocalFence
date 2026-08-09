# LocalFence

LocalFence is a free, open-source local network inventory and reversible access
control app for rootless jailbroken iPhones. It is an independent educational
project built with UIKit, Theos, and a restricted root launch daemon.

Use it only on a private network you own or are explicitly authorized to
administer.

## Features

- Native UIKit interface for discovering and managing LAN devices.
- Best-effort device names and platform categories such as iPhone, iPad, Mac,
  Apple TV, Windows, Linux, Android, Android TV, and network appliances.
- Offline MA-L, MA-M, and MA-S vendor lookup with longest-prefix matching.
- Clear High, Medium, Low, or Unknown confidence on platform guesses.
- Recognition of private or randomized MAC addresses without assigning a
  misleading hardware vendor.
- Persistent root launch daemon; active operations do not depend on keeping the
  app in the foreground.
- Authenticated Unix-domain IPC with peer UID, PID, and executable validation.
- Discovery restricted to private IPv4 Wi-Fi LANs between /22 and /30.
- Target IP/MAC revalidation immediately before an operation starts.
- Reversible per-device controls with corrective router mappings on restore.
- Intervals from 5 ms to 5 seconds, including advanced 5, 10, 20, and 50 ms
  choices. A global traffic ceiling limits combined high-rate selections.
- Up to 255 selected devices.
- Restricted command-line client for diagnostics and administration.
- No analytics, advertising, accounts, cloud backend, credential collection,
  traffic forwarding, or payload capture.

## Device identification

Identification is evidence-based and intentionally conservative:

1. Bonjour hostnames and advertised service types provide the strongest local
   clues. For example, an explicit iPhone name can produce a high-confidence
   iPhone label, while Google Cast alone produces a broader Android TV / Cast
   category.
2. The OUI database maps the globally assigned prefix of a MAC address to the
   organization that registered it.
3. Vendor-only platform guesses are labeled Low confidence because a vendor
   can manufacture many unrelated products.

An OUI database does **not** contain the exact model, device owner, hostname,
or operating system. Modern iOS, Android, Windows, and other devices frequently
use private MAC addresses; LocalFence labels these as private/randomized and
does not invent a vendor. Results are hints, not identity proof.

The bundled database is generated from the BSD-2-Clause `oui-data` project.
See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). To refresh it:

    ./scripts/update-oui.py

## Requirements

- A rootless jailbreak such as Dopamine.
- iOS 16 or newer.
- Wi-Fi on a private IPv4 subnet.
- The `network-cmds` package.
- macOS with full Xcode and Theos to build.

The current release supports Wi-Fi interface `en0`. Hotspot management and
IPv6 access control are outside the current scope.

## Build on macOS

Install Theos at `~/theos`, then run:

    git clone https://github.com/emp0ry/LocalFence.git
    cd LocalFence
    ./scripts/build.sh

To use a different Theos installation:

    THEOS=/path/to/theos ./scripts/build.sh

The rootless Debian package is written to `packages/`.

## Install

    scp packages/com.emp0ry.localfence_*.deb root@iphone:/var/tmp/
    ssh root@iphone
    apt install /var/tmp/com.emp0ry.localfence_*.deb

Open LocalFence, accept the authorized-use notice, and allow Location and Local
Network access. Location authorization is required by iOS for Wi-Fi-related
information; LocalFence does not request location updates or read coordinates.
Local Network access permits Bonjour identity evidence.

If the app reports that the daemon is unavailable, reinstall the latest
package so the rootless launch daemon and authenticated IPC socket are
recreated, then reopen the app.

## CLI

    localfencectl status
    localfencectl scan
    localfencectl block 192.168.1.25 aa:bb:cc:dd:ee:ff 500
    localfencectl unblock 192.168.1.25
    localfencectl stop

The daemon accepts the CLI only when its peer UID is root and its executable
path ends in `/usr/bin/localfencectl`.

## Safety

Short intervals increase LAN traffic and device CPU use. Start with 500 ms and
reduce only when necessary on a network you administer. The daemon enforces
private-LAN scope, a 255-device maximum, and an aggregate send-event ceiling;
these technical controls do not replace authorization or good judgment.

See [SECURITY.md](SECURITY.md), [PRIVACY.md](PRIVACY.md), and
[LEGAL.md](LEGAL.md) before publishing or distributing a build.

## License

LocalFence is licensed under the GNU General Public License, version 3 or any
later version (`GPL-3.0-or-later`). See [LICENSE](LICENSE).
