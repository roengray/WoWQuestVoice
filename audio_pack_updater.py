"""Download and atomically install WoWQuestVoice audio update packages."""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import time
import urllib.request
import zipfile
from pathlib import Path, PurePosixPath
from typing import Any

import quest_data_uploader as collector


STATE_PATH = collector.LOCAL_ROOT / "audio_update_state.json"
DOWNLOAD_ROOT = collector.LOCAL_ROOT / "audio_downloads"
STAGING_ROOT = collector.LOCAL_ROOT / "audio_staging"
ALLOWED_ROOT_FILES = {"QuestAudioData.lua"}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def addon_path(config: dict[str, Any]) -> Path:
    game = Path(str(config.get("gamePath") or collector.infer_game_path()))
    return game / "Interface" / "AddOns" / "WoWQuestVoice"


def fetch_manifest(config: dict[str, Any]) -> dict[str, Any]:
    endpoint = str(config.get("endpoint") or "").rstrip("/")
    if not endpoint.startswith("https://"):
        raise RuntimeError("HTTPS update endpoint is missing")
    request = urllib.request.Request(
        endpoint + "/v1/audio/manifest",
        headers={"User-Agent": "WoWQuestVoice-Updater/0.1"},
    )
    with urllib.request.urlopen(request, timeout=30, context=collector.tls_context()) as response:
        manifest = json.loads(response.read().decode("utf-8"))
    if manifest.get("schemaVersion") != 1 or not isinstance(manifest.get("packages"), list):
        raise RuntimeError("invalid audio manifest")
    return manifest


def wow_is_running() -> bool:
    if os.name != "nt":
        return False
    result = subprocess.run(
        ["tasklist.exe", "/FO", "CSV", "/NH"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        check=False,
    )
    for line in result.stdout.splitlines():
        image = line.split(",", 1)[0].strip().strip('"').lower()
        if image in {"wow.exe", "wowclassic.exe", "wowclassicb.exe", "wowt.exe", "wowb.exe"}:
            return True
    return False


def validate_package(row: dict[str, Any]) -> tuple[str, str, int, str]:
    package_id = str(row.get("id") or "")
    url = str(row.get("url") or "")
    expected_hash = str(row.get("sha256") or "").lower()
    size = int(row.get("size") or 0)
    if not package_id or not url.startswith("https://"):
        raise RuntimeError("invalid package metadata")
    if len(expected_hash) != 64 or any(char not in "0123456789abcdef" for char in expected_hash):
        raise RuntimeError("invalid package hash")
    if size < 1 or size > 1024 * 1024 * 1024:
        raise RuntimeError("invalid package size")
    return package_id, url, size, expected_hash


def download_package(row: dict[str, Any], release_dir: Path) -> Path:
    package_id, url, expected_size, expected_hash = validate_package(row)
    filename = Path(urllib.request.urlparse(url).path).name if hasattr(urllib.request, "urlparse") else ""
    if not filename:
        from urllib.parse import urlparse

        filename = Path(urlparse(url).path).name
    if not filename.endswith(".zip"):
        raise RuntimeError("invalid package filename")

    release_dir.mkdir(parents=True, exist_ok=True)
    final_path = release_dir / filename
    part_path = final_path.with_suffix(final_path.suffix + ".part")
    if final_path.exists() and final_path.stat().st_size == expected_size:
        if sha256_file(final_path) == expected_hash:
            return final_path
        final_path.unlink()

    offset = part_path.stat().st_size if part_path.exists() else 0
    headers = {"User-Agent": "WoWQuestVoice-Updater/0.1"}
    if 0 < offset < expected_size:
        headers["Range"] = f"bytes={offset}-"
    else:
        offset = 0
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=90, context=collector.tls_context()) as response:
        append = offset > 0 and response.status == 206
        if not append:
            offset = 0
        with part_path.open("ab" if append else "wb") as stream:
            shutil.copyfileobj(response, stream, length=1024 * 1024)

    if part_path.stat().st_size != expected_size or sha256_file(part_path) != expected_hash:
        raise RuntimeError(f"package verification failed: {package_id}")
    part_path.replace(final_path)
    return final_path


def safe_members(archive: zipfile.ZipFile) -> list[zipfile.ZipInfo]:
    accepted: list[zipfile.ZipInfo] = []
    for info in archive.infolist():
        path = PurePosixPath(info.filename)
        if info.is_dir():
            continue
        if path.is_absolute() or ".." in path.parts:
            raise RuntimeError("unsafe archive path")
        allowed = info.filename in ALLOWED_ROOT_FILES or (
            len(path.parts) >= 3 and path.parts[0] == "sounds" and info.filename.endswith(".ogg")
        )
        if not allowed:
            raise RuntimeError(f"unexpected archive file: {info.filename}")
        accepted.append(info)
    return accepted


def stage_packages(packages: list[Path], version: str) -> Path:
    staging = (STAGING_ROOT / version).resolve()
    root = STAGING_ROOT.resolve()
    if root not in staging.parents:
        raise RuntimeError("invalid staging path")
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir(parents=True)
    for package in packages:
        with zipfile.ZipFile(package) as archive:
            members = safe_members(archive)
            archive.extractall(staging, members=members)
    return staging


def apply_staging(staging: Path, addon: Path) -> int:
    addon = addon.resolve()
    if not (addon / "WoWQuestVoice.toc").exists():
        raise RuntimeError("WoWQuestVoice addon folder was not found")
    installed = 0
    for source in sorted(path for path in staging.rglob("*") if path.is_file()):
        relative = source.relative_to(staging)
        destination = (addon / relative).resolve()
        if addon not in destination.parents:
            raise RuntimeError("update escaped addon folder")
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = destination.with_suffix(destination.suffix + ".wqv-new")
        shutil.copy2(source, temporary)
        os.replace(temporary, destination)
        installed += 1
    return installed


def check_and_update(config: dict[str, Any]) -> dict[str, Any]:
    manifest = fetch_manifest(config)
    version = str(manifest.get("version") or "0")
    state = collector.load_json(STATE_PATH, {"packages": {}})
    installed_hashes = state.get("packages") if isinstance(state.get("packages"), dict) else {}
    bootstrap_packages = manifest.get("bootstrapPackages")
    if not isinstance(bootstrap_packages, list):
        # Compatibility with the short-lived single-bootstrap manifest.
        legacy_bootstrap = manifest.get("bootstrap")
        bootstrap_packages = [legacy_bootstrap] if isinstance(legacy_bootstrap, dict) else []
    if not installed_hashes and bootstrap_packages:
        for row in bootstrap_packages:
            validate_package(row)
        release_dir = DOWNLOAD_ROOT / version
        downloaded = [download_package(row, release_dir) for row in bootstrap_packages]
        staging = stage_packages(downloaded, version)
        if wow_is_running():
            return {"status": "staged-bootstrap", "version": version, "packages": len(downloaded)}
        installed_files = apply_staging(staging, addon_path(config))
        installed_hashes = {
            str(row["id"]): str(row["sha256"])
            for row in manifest["packages"]
            if isinstance(row, dict) and row.get("id") and row.get("sha256")
        }
        collector.save_json(
            STATE_PATH,
            {
                "version": version,
                "packages": installed_hashes,
                "bootstrapHashes": {
                    str(row["id"]): str(row["sha256"])
                    for row in bootstrap_packages
                },
                "lastSuccess": int(time.time()),
            },
        )
        return {
            "status": "installed-bootstrap",
            "version": version,
            "packages": len(downloaded),
            "files": installed_files,
        }
    changed = []
    for row in manifest["packages"]:
        package_id, _, _, expected_hash = validate_package(row)
        if installed_hashes.get(package_id) != expected_hash:
            changed.append(row)
    if not changed:
        return {"status": "current", "version": version, "packages": 0}

    release_dir = DOWNLOAD_ROOT / version
    downloaded = [download_package(row, release_dir) for row in changed]
    staging = stage_packages(downloaded, version)
    if wow_is_running():
        return {"status": "staged", "version": version, "packages": len(changed)}

    installed_files = apply_staging(staging, addon_path(config))
    for row in changed:
        installed_hashes[str(row["id"])] = str(row["sha256"])
    collector.save_json(
        STATE_PATH,
        {
            "version": version,
            "packages": installed_hashes,
            "lastSuccess": int(time.time()),
        },
    )
    return {
        "status": "installed",
        "version": version,
        "packages": len(changed),
        "files": installed_files,
    }
