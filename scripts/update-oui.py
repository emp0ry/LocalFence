#!/usr/bin/env python3
"""Build LocalFence's compact offline OUI database from oui-data."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import sqlite3
import tempfile
import urllib.request
from typing import Optional


SOURCE_COMMIT = "aa9601d50925536e985dbc5081a33cc7171c9090"
SOURCE_URL = (
    "https://raw.githubusercontent.com/silverwind/oui-data/"
    f"{SOURCE_COMMIT}/index.json"
)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source",
        type=pathlib.Path,
        help="Use an existing oui-data index.json instead of downloading it.",
    )
    parser.add_argument(
        "--output",
        type=pathlib.Path,
        default=pathlib.Path("app/Resources/OUI.sqlite"),
    )
    return parser.parse_args()


def load_source(path: Optional[pathlib.Path]) -> bytes:
    if path is not None:
        return path.read_bytes()
    request = urllib.request.Request(
        SOURCE_URL, headers={"User-Agent": "LocalFence-OUI-Updater/1"}
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read()


def build_database(source: bytes, output: pathlib.Path) -> None:
    decoded = json.loads(source)
    if not isinstance(decoded, dict):
        raise ValueError("oui-data root must be a JSON object")

    output.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix="OUI-", suffix=".sqlite", dir=output.parent
    )
    os.close(descriptor)
    temporary = pathlib.Path(temporary_name)

    try:
        connection = sqlite3.connect(temporary)
        connection.executescript(
            """
            PRAGMA journal_mode=OFF;
            PRAGMA synchronous=OFF;
            PRAGMA page_size=4096;
            CREATE TABLE vendor (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL UNIQUE
            );
            CREATE TABLE prefix (
                value TEXT PRIMARY KEY,
                vendor_id INTEGER NOT NULL REFERENCES vendor(id)
            ) WITHOUT ROWID;
            CREATE TABLE metadata (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            ) WITHOUT ROWID;
            """
        )

        vendor_ids: dict[str, int] = {}
        for prefix, details in sorted(decoded.items()):
            normalized = str(prefix).strip().upper()
            if len(normalized) not in (6, 7, 9) or any(
                character not in "0123456789ABCDEF" for character in normalized
            ):
                raise ValueError(f"invalid OUI prefix: {prefix!r}")
            first_line = str(details).splitlines()[0].strip()
            vendor = first_line or "Private registration"
            vendor_id = vendor_ids.get(vendor)
            if vendor_id is None:
                cursor = connection.execute(
                    "INSERT INTO vendor(name) VALUES (?)", (vendor,)
                )
                vendor_id = int(cursor.lastrowid)
                vendor_ids[vendor] = vendor_id
            connection.execute(
                "INSERT INTO prefix(value, vendor_id) VALUES (?, ?)",
                (normalized, vendor_id),
            )

        metadata = {
            "source": SOURCE_URL,
            "source_commit": SOURCE_COMMIT,
            "source_sha256": hashlib.sha256(source).hexdigest(),
            "source_license": "BSD-2-Clause",
            "record_count": str(len(decoded)),
        }
        connection.executemany(
            "INSERT INTO metadata(key, value) VALUES (?, ?)", metadata.items()
        )
        connection.commit()
        connection.execute("VACUUM")
        connection.close()
        os.replace(temporary, output)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise


def main() -> None:
    arguments = parse_arguments()
    source = load_source(arguments.source)
    build_database(source, arguments.output)
    print(f"Wrote {arguments.output}")


if __name__ == "__main__":
    main()
