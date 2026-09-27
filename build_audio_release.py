"""Build immutable WoWQuestVoice audio update archives and a signed-by-hash manifest."""

from __future__ import annotations

import argparse
import hashlib
import json
import zipfile
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parent
ADDON = ROOT / "WoWQuestVoice"
DEFAULT_OUTPUT = ROOT / "release" / "audio"
DOWNLOAD_BASE = "https://wowquestvoice-collector.wowquestvoice-ko.workers.dev/v1/audio/files"


def file_hash(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def package_row(package_id: str, archive: Path) -> dict:
    return {
        "id": package_id,
        "file": archive.name,
        "url": f"{DOWNLOAD_BASE}/{archive.name}",
        "size": archive.stat().st_size,
        "sha256": file_hash(archive),
    }


def add_package(packages: list[dict], package_id: str, archive: Path) -> None:
    packages.append(package_row(package_id, archive))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", default=datetime.now().strftime("%Y.%m.%d.%H%M"))
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    release_dir = args.output / args.version
    if release_dir.joinpath("manifest.json").exists() and not args.force:
        parser.error("release version already exists; choose a new --version or pass --force")
    release_dir.mkdir(parents=True, exist_ok=True)
    packages: list[dict] = []

    core_archive = release_dir / f"core-data-{args.version}.zip"
    with zipfile.ZipFile(core_archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        archive.write(ADDON / "QuestAudioData.lua", "QuestAudioData.lua")
    add_package(packages, "core-data", core_archive)

    sounds = ADDON / "sounds"
    for shard in sorted(path for path in sounds.iterdir() if path.is_dir()):
        archive_path = release_dir / f"sounds-{shard.name}-{args.version}.zip"
        with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_STORED) as archive:
            for sound in sorted(shard.rglob("*.ogg")):
                archive.write(sound, sound.relative_to(ADDON).as_posix())
        add_package(packages, f"sounds-{shard.name}", archive_path)

    # Wrangler's direct R2 uploader accepts at most 300 MiB per object. Keep the
    # initial install to two requests while leaving plenty of headroom for growth.
    all_sounds = sorted(sounds.rglob("*.ogg"))
    midpoint = (len(all_sounds) + 1) // 2
    bootstrap_packages: list[dict] = []
    for index, selected in enumerate((all_sounds[:midpoint], all_sounds[midpoint:]), start=1):
        bootstrap_archive = release_dir / f"bootstrap-{index:02d}-{args.version}.zip"
        with zipfile.ZipFile(bootstrap_archive, "w", compression=zipfile.ZIP_STORED) as archive:
            if index == 1:
                archive.write(ADDON / "QuestAudioData.lua", "QuestAudioData.lua")
            for sound in selected:
                archive.write(sound, sound.relative_to(ADDON).as_posix())
        bootstrap_packages.append(package_row(f"bootstrap-{index:02d}", bootstrap_archive))

    manifest = {
        "schemaVersion": 1,
        "version": args.version,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "bootstrapPackages": bootstrap_packages,
        "packages": packages,
    }
    manifest_path = release_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")

    print(json.dumps({
        "version": args.version,
        "packages": len(packages),
        "incrementalBytes": sum(row["size"] for row in packages),
        "bootstrapPackages": len(bootstrap_packages),
        "bootstrapBytes": sum(row["size"] for row in bootstrap_packages),
        "manifest": str(manifest_path),
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
