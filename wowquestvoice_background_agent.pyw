"""Headless WoWQuestVoice collection and audio update loop."""

from __future__ import annotations

import argparse
import ctypes
import os
import sys
import time
import traceback
from datetime import datetime

import audio_pack_updater as updater
import quest_data_uploader as collector


MUTEX_NAME = "Local\\WoWQuestVoiceBackgroundAgent"
LOG_PATH = collector.LOCAL_ROOT / "background_agent.log"
AGENT_STATE_PATH = collector.LOCAL_ROOT / "background_agent_state.json"


def log(message: str) -> None:
    collector.LOCAL_ROOT.mkdir(parents=True, exist_ok=True)
    if LOG_PATH.exists() and LOG_PATH.stat().st_size > 512 * 1024:
        LOG_PATH.replace(LOG_PATH.with_suffix(".log.old"))
    stamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with LOG_PATH.open("a", encoding="utf-8") as stream:
        stream.write(f"[{stamp}] {message}\n")


def acquire_mutex() -> bool:
    handle = ctypes.windll.kernel32.CreateMutexW(None, False, MUTEX_NAME)
    if not handle:
        return False
    acquire_mutex.handle = handle
    return ctypes.windll.kernel32.GetLastError() != 183


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--configure", action="store_true")
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--game-path")
    parser.add_argument("--enable-upload", action="store_true")
    parser.add_argument("--disable-upload", action="store_true")
    parser.add_argument("--enable-updates", action="store_true")
    parser.add_argument("--disable-updates", action="store_true")
    return parser.parse_args()


def configure(args: argparse.Namespace) -> dict:
    config = collector.load_json(collector.CONFIG_PATH, collector.default_config())
    public = collector.public_config()
    if public.get("endpoint"):
        config["endpoint"] = str(public["endpoint"])
    if public.get("uploadToken"):
        config["uploadToken"] = str(public["uploadToken"])
    else:
        config.pop("uploadToken", None)
    if args.game_path:
        config["gamePath"] = os.path.abspath(os.path.expandvars(args.game_path))
    if args.enable_upload:
        config["uploadEnabled"] = True
        config["enabled"] = True  # compatibility with earlier builds
    if args.disable_upload:
        config["uploadEnabled"] = False
        config["enabled"] = False
    if args.enable_updates:
        config["updateEnabled"] = True
    if args.disable_updates:
        config["updateEnabled"] = False
    if args.configure or args.game_path or args.enable_upload or args.disable_upload \
            or args.enable_updates or args.disable_updates or not collector.CONFIG_PATH.exists():
        collector.save_json(collector.CONFIG_PATH, config)
    return config


def main() -> None:
    args = parse_args()
    config = configure(args)
    if args.configure:
        return
    if not acquire_mutex():
        return
    log("background agent started")
    while True:
        config = collector.load_json(collector.CONFIG_PATH, collector.default_config())
        upload_enabled = bool(config.get("uploadEnabled", config.get("enabled", False)))
        update_enabled = bool(config.get("updateEnabled", True))
        if not upload_enabled and not update_enabled:
            log("automatic collection and updates disabled; stopping")
            return
        captured = uploaded = 0
        update = {"status": "disabled", "version": ""}
        if upload_enabled:
            try:
                captured, uploaded = collector.upload_once(config)
            except Exception as exc:
                log(f"collection sync failed: {exc}\n{traceback.format_exc()}")

        agent_state = collector.load_json(AGENT_STATE_PATH, {})
        now = int(time.time())
        audio_interval = max(3600, int(config.get("audioCheckSeconds") or 86400))
        last_success = int(agent_state.get("lastAudioSuccess") or 0)
        last_attempt = int(agent_state.get("lastAudioAttempt") or 0)
        audio_due = args.once or (
            (last_success == 0 or now - last_success >= audio_interval)
            and (last_attempt == 0 or now - last_attempt >= 900)
        )
        if update_enabled and audio_due:
            try:
                agent_state["lastAudioAttempt"] = now
                collector.save_json(AGENT_STATE_PATH, agent_state)
                update = updater.check_and_update(config)
                agent_state["lastAudioSuccess"] = int(time.time())
                collector.save_json(AGENT_STATE_PATH, agent_state)
            except Exception as exc:
                update = {"status": "failed", "version": ""}
                log(f"audio update failed: {exc}\n{traceback.format_exc()}")
        elif update_enabled:
            update = {"status": "not-due", "version": ""}

        log(
            f"sync captured={captured} uploaded={uploaded} "
            f"audio={update.get('status')} version={update.get('version')}"
        )
        if args.once:
            return
        time.sleep(max(60, int(config.get("pollSeconds") or 60)))


if __name__ == "__main__":
    main()
