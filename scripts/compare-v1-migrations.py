#!/usr/bin/env python3
"""Compare two SQL files without changing files or connecting to a database."""

import argparse
import hashlib
import json
from pathlib import Path


def normalize_newlines(content):
    # Preserve spaces, comments and blank lines; allow one final line terminator.
    return content.replace(b"\r\n", b"\n").replace(b"\r", b"\n").removesuffix(b"\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("infra", type=Path, help="Infra V1 SQL file")
    parser.add_argument("backend", type=Path, help="Backend V1 SQL file")
    args = parser.parse_args()

    contents = []
    sources = {}
    for name, path in (("infra", args.infra), ("backend", args.backend)):
        try:
            content = path.read_bytes()
        except OSError as error:
            parser.exit(2, f"Cannot read {name} SQL file: {error}\n")
        contents.append(content)
        sources[name] = {
            "path": str(path),
            "bytes": len(content),
            "sha256": hashlib.sha256(content).hexdigest(),
            "ends_with_newline": content.endswith((b"\n", b"\r")),
        }

    infra, backend = contents
    if infra == backend:
        comparison = "identical"
    elif normalize_newlines(infra) == normalize_newlines(backend):
        comparison = "line_endings_only"
    else:
        comparison = "different"

    print(json.dumps({"comparison": comparison, **sources}, indent=2))
    return 1 if comparison == "different" else 0


if __name__ == "__main__":
    raise SystemExit(main())
