#!/usr/bin/env python3
"""Verify the supplied AMD64 model ZIP and install one complete, immutable directory."""

import argparse
import hashlib
import os
from pathlib import Path
import shutil
import stat
import sys
import tempfile
import zipfile


MODEL = "koen-e5-tiny-q8"
# Backend deployment contract, section 11, revision c3a45a9.
FILES = {
    "manifest.json": (426, "c1ef84e7200635659580ea2e057f0b6c4d2fe9f56b5bc80f4b4ccf3385450f98"),
    "model_quint8_x86_64.onnx": (38275821, "ef00d6227284038a3338a92273ca0e89971f93f966ab5eabfd6a8fc0bea9459e"),
    "tokenizer.json": (2931715, "a6dd38d692ac1caa6d5dbc195d92f1f978b5c74ec60e02ed15fdf04404742fe3"),
}


def checksum(source):
    digest = hashlib.sha256()
    for chunk in iter(lambda: source.read(65536), b""):
        digest.update(chunk)
    return digest.hexdigest()


def verify_archive(archive):
    with zipfile.ZipFile(archive) as bundle:
        entries = bundle.infolist()
        names = [entry.filename for entry in entries]
        required = {f"{MODEL}/{name}" for name in FILES}
        if len(names) != len(set(names)) or set(names) - {f"{MODEL}/"} != required:
            raise ValueError("ZIP must contain only the three pinned model files and their directory.")
        for entry in entries:
            mode = entry.external_attr >> 16
            if stat.S_ISLNK(mode):
                raise ValueError("ZIP symlinks are not allowed.")
            if entry.filename == f"{MODEL}/":
                continue
            size, digest = FILES[entry.filename.split("/")[-1]]
            if entry.file_size != size:
                raise ValueError(f"Unexpected size: {entry.filename}")
            with bundle.open(entry) as source:
                actual = checksum(source)
            if actual != digest:
                raise ValueError(f"Checksum mismatch: {entry.filename}")


def verify_directory(directory):
    if directory.is_symlink() or not directory.is_dir():
        raise ValueError("Destination must be a real directory.")
    if {p.name for p in directory.iterdir()} != set(FILES):
        raise ValueError("Existing destination is incomplete or contains unexpected files.")
    for name, (size, digest) in FILES.items():
        path = directory / name
        if path.is_symlink() or not path.is_file() or path.stat().st_size != size:
            raise ValueError(f"Invalid installed file: {name}")
        with path.open("rb") as source:
            if checksum(source) != digest:
                raise ValueError(f"Installed checksum mismatch: {name}")


def install(archive, destination):
    # Keep a verified private copy: never extract an archive that changed after verification.
    with tempfile.TemporaryDirectory(prefix="openstudy-model-") as temporary:
        snapshot = Path(temporary) / "model.zip"
        shutil.copyfile(archive, snapshot)
        verify_archive(snapshot)
        # Docker can create an empty bind-mount path before a replacement host is ready.
        # Replace that empty directory atomically; preserve any nonempty invalid release.
        empty_directory = destination.is_dir() and not destination.is_symlink() and not any(destination.iterdir())
        if (destination.exists() or destination.is_symlink()) and not empty_directory:
            verify_directory(destination)
            destination.chmod(0o755)
            for name in FILES:
                (destination / name).chmod(0o644)
            return
        destination.parent.mkdir(parents=True, exist_ok=True, mode=0o755)
        staging = Path(tempfile.mkdtemp(prefix=".model-", dir=destination.parent))
        try:
            with zipfile.ZipFile(snapshot) as bundle:
                for name in FILES:
                    with bundle.open(f"{MODEL}/{name}") as source, (staging / name).open("wb") as target:
                        shutil.copyfileobj(source, target)
                    (staging / name).chmod(0o644)
            staging.chmod(0o755)
            verify_directory(staging)
            os.rename(staging, destination)
        finally:
            if staging.exists():
                shutil.rmtree(staging)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", required=True, type=Path)
    choice = parser.add_mutually_exclusive_group(required=True)
    choice.add_argument("--verify-only", action="store_true")
    choice.add_argument("--destination", type=Path)
    args = parser.parse_args()
    try:
        if args.verify_only:
            verify_archive(args.archive)
        else:
            install(args.archive, args.destination)
    except (OSError, ValueError, RuntimeError, zipfile.BadZipFile) as error:
        print(f"Model preparation failed: {error}", file=sys.stderr)
        return 1
    print("Verified koen-e5-tiny-q8: linux/amd64, 384 dimensions, all three SHA-256 checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
