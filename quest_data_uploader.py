"""Upload anonymous WoWQuestVoice SavedVariables captures in the background.

The uploader stays disabled until the player explicitly opts in.  It transmits
only quest ID, section, title, text, locale, client build and addon version.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import ssl
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


FROZEN = bool(getattr(sys, "frozen", False))
ROOT = Path(sys.executable).resolve().parent if FROZEN else Path(__file__).resolve().parent
LOCAL_ROOT = Path(os.environ.get("LOCALAPPDATA") or ROOT) / "WoWQuestVoice"
CONFIG_PATH = LOCAL_ROOT / "collector_uploader.json"
STATE_PATH = LOCAL_ROOT / "collector_uploader_state.json"
_BUNDLE_ROOT = Path(getattr(sys, "_MEIPASS", ROOT))
PUBLIC_CONFIG_PATH = (
    ROOT / "collector_public_config.json"
    if (ROOT / "collector_public_config.json").exists()
    else _BUNDLE_ROOT / "collector_public_config.json"
)
VALID_SECTIONS = {"accept", "progress", "complete"}


def tls_context() -> ssl.SSLContext:
    # truststore uses the Windows certificate store, matching the browser and
    # avoiding stale bundled CA data in long-lived packaged executables.
    try:
        import truststore

        return truststore.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    except ImportError:
        return ssl.create_default_context()


def configure_lupa() -> None:
    candidates = [ROOT / ".tools"]
    for candidate in candidates:
        if candidate.exists() and str(candidate) not in sys.path:
            sys.path.insert(0, str(candidate))


def lua_to_python(value: Any) -> Any:
    from lupa.lua54 import lua_type

    if lua_type(value) != "table":
        return value
    return {lua_to_python(key): lua_to_python(item) for key, item in value.items()}


def infer_game_path() -> Path:
    # A distributed collector lives beside WoWQuestVoice.toc.
    if (ROOT / "WoWQuestVoice.toc").exists() and len(ROOT.parents) >= 3:
        return ROOT.parents[2]
    for variable in ("ProgramFiles(x86)", "ProgramFiles"):
        base = os.environ.get(variable)
        if not base:
            continue
        candidate = Path(base) / "World of Warcraft" / "_classic_beta_"
        if candidate.exists():
            return candidate
    return Path()


def public_config() -> dict[str, Any]:
    return load_json(PUBLIC_CONFIG_PATH, {"endpoint": "", "uploadToken": ""})


def default_config() -> dict[str, Any]:
    public = public_config()
    return {
        "enabled": False,
        "uploadEnabled": False,
        "updateEnabled": True,
        "endpoint": str(public.get("endpoint") or ""),
        "uploadToken": str(public.get("uploadToken") or ""),
        "gamePath": str(infer_game_path()),
        "pollSeconds": 60,
        "audioCheckSeconds": 86400,
    }


def load_json(path: Path, fallback: dict[str, Any]) -> dict[str, Any]:
    if not path.exists():
        return fallback.copy()
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else fallback.copy()
    except (OSError, ValueError):
        return fallback.copy()


def save_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")
    temp.replace(path)


def addon_version(game_path: Path) -> str:
    toc = game_path / "Interface" / "AddOns" / "WoWQuestVoice" / "WoWQuestVoice.toc"
    if not toc.exists():
        return ""
    match = re.search(r"^##\s*Version:\s*(.+?)\s*$", toc.read_text(encoding="utf-8-sig"), re.M)
    return match.group(1).strip()[:24] if match else ""


def client_build(game_path: Path) -> str:
    build_info = game_path.parent / ".build.info"
    if not build_info.exists():
        return ""
    try:
        lines = build_info.read_text(encoding="utf-8-sig", errors="replace").splitlines()
        return lines[1][:40] if len(lines) > 1 else ""
    except OSError:
        return ""


def saved_variable_paths(game_path: Path) -> list[Path]:
    account = game_path / "WTF" / "Account"
    if not account.exists():
        return []
    return sorted(account.glob("*/SavedVariables/WoWQuestVoice.lua"))


def load_captures(path: Path) -> dict[Any, Any]:
    configure_lupa()
    from lupa.lua54 import LuaRuntime

    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(path.read_text(encoding="utf-8-sig"))
    database = lua.globals().WoWQuestVoiceDB
    if database is None or database["capturedQuests"] is None:
        return {}
    return lua_to_python(database["capturedQuests"])


def collect_records(game_path: Path) -> list[dict[str, Any]]:
    records: dict[str, dict[str, Any]] = {}
    for path in saved_variable_paths(game_path):
        try:
            captures = load_captures(path)
        except Exception as exc:
            print(f"warning: could not read {path}: {exc}", file=sys.stderr)
            continue
        for raw_id, sections in captures.items():
            try:
                quest_id = int(raw_id)
            except (TypeError, ValueError):
                continue
            if not isinstance(sections, dict):
                continue
            for section, row in sections.items():
                section = str(section)
                if section not in VALID_SECTIONS or not isinstance(row, dict):
                    continue
                title = str(row.get("title") or "").replace("\x00", "").strip()[:512]
                text = str(row.get("text") or "").replace("\x00", "").strip()[:16000]
                if not text:
                    continue
                record = {"questId": quest_id, "section": section, "title": title, "text": text}
                digest = hashlib.sha256(
                    json.dumps(record, ensure_ascii=False, sort_keys=True).encode("utf-8")
                ).hexdigest()
                records[digest] = record
    return [dict(record, localHash=digest) for digest, record in sorted(records.items())]


def upload_once(config: dict[str, Any], *, dry_run: bool = False) -> tuple[int, int]:
    game_path = Path(os.path.expandvars(str(config.get("gamePath") or infer_game_path())))
    all_records = collect_records(game_path)
    state = load_json(STATE_PATH, {"sent": []})
    sent = {str(value) for value in state.get("sent", [])}
    pending = [record for record in all_records if record["localHash"] not in sent]
    if dry_run:
        print(f"captured={len(all_records)} pending={len(pending)}")
        return len(all_records), len(pending)
    if not config.get("uploadEnabled", config.get("enabled", False)):
        raise RuntimeError("automatic upload is disabled; explicit opt-in is required")
    endpoint = str(config.get("endpoint") or "").rstrip("/")
    if not endpoint.startswith("https://") and not endpoint.startswith("http://127.0.0.1"):
        raise RuntimeError("a valid HTTPS collector endpoint is required")
    token = str(config.get("uploadToken") or "")
    if not token:
        raise RuntimeError("upload token is missing")

    uploaded = 0
    for offset in range(0, len(pending), 100):
        batch = pending[offset : offset + 100]
        payload = {
            "schemaVersion": 1,
            "locale": "koKR",
            "clientBuild": client_build(game_path),
            "addonVersion": addon_version(game_path),
            "records": [{key: value for key, value in row.items() if key != "localHash"} for row in batch],
        }
        request = urllib.request.Request(
            endpoint + "/v1/quests",
            data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
                "User-Agent": "WoWQuestVoice-Collector/0.1",
            },
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=30, context=tls_context()) as response:
            result = json.loads(response.read().decode("utf-8"))
        if not result.get("ok") or int(result.get("accepted", 0)) != len(batch):
            raise RuntimeError(f"collector rejected batch: {result}")
        sent.update(row["localHash"] for row in batch)
        uploaded += len(batch)
        state = {"sent": sorted(sent), "lastSuccess": int(time.time())}
        save_json(STATE_PATH, state)
    return len(all_records), uploaded


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--watch", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--enable", action="store_true", help="record explicit upload consent")
    parser.add_argument("--disable", action="store_true")
    parser.add_argument("--endpoint")
    parser.add_argument("--token")
    args = parser.parse_args()

    config = load_json(CONFIG_PATH, default_config())
    if args.endpoint:
        config["endpoint"] = args.endpoint
    if args.token:
        config["uploadToken"] = args.token
    if args.enable:
        config["enabled"] = True
    if args.disable:
        config["enabled"] = False
    if args.endpoint or args.token or args.enable or args.disable or not CONFIG_PATH.exists():
        save_json(CONFIG_PATH, config)

    if args.dry_run:
        upload_once(config, dry_run=True)
        return
    if not args.once and not args.watch:
        parser.error("choose --once, --watch or --dry-run")
    while True:
        try:
            captured, uploaded = upload_once(config)
            print(f"captured={captured} uploaded={uploaded}")
        except (OSError, RuntimeError, urllib.error.URLError) as exc:
            print(f"upload warning: {exc}", file=sys.stderr)
        if not args.watch:
            return
        time.sleep(max(15, int(config.get("pollSeconds") or 30)))


if __name__ == "__main__":
    main()
