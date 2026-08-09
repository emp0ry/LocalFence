# Daemon protocol

LocalFence uses one JSON request and one JSON response per Unix-domain socket
connection. The socket is at
`/var/mobile/Library/LocalFence/localfence.sock`.

Every response contains an ok Boolean and, on failure, an error string.

## Requests

Status:

    {"command": "status"}

Scan:

    {"command": "scan"}

Block:

    {
      "command": "block",
      "ip": "192.168.1.25",
      "mac": "aa:bb:cc:dd:ee:ff",
      "intervalMs": 500
    }

Unblock:

    {"command": "unblock", "ip": "192.168.1.25"}

Stop all:

    {"command": "stop"}

Unknown fields are ignored. Unknown commands, malformed values, oversized
requests, and unauthorized peers are rejected.

`intervalMs` accepts 5 through 5000 ms. The daemon supports at most 255 active
device entries and rejects changes that would exceed its aggregate send-event
ceiling.
