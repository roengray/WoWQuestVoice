"""Verify that every published audio object exists with the manifest size."""

from __future__ import annotations

import json
import re
import urllib.request

import quest_data_uploader as collector


MANIFEST_URL = (
    "https://wowquestvoice-collector.wowquestvoice-ko.workers.dev/v1/audio/manifest"
)


def main() -> None:
    context = collector.tls_context()
    manifest_request = urllib.request.Request(
        MANIFEST_URL, headers={"User-Agent": "WoWQuestVoice-ReleaseVerifier/0.1"}
    )
    with urllib.request.urlopen(manifest_request, timeout=30, context=context) as response:
        manifest = json.load(response)

    rows = list(manifest.get("bootstrapPackages") or []) + list(manifest.get("packages") or [])
    for index, row in enumerate(rows, 1):
        request = urllib.request.Request(
            row["url"],
            headers={
                "User-Agent": "WoWQuestVoice-ReleaseVerifier/0.1",
                "Range": "bytes=0-0",
            },
        )
        with urllib.request.urlopen(request, timeout=30, context=context) as response:
            content_range = response.headers.get("Content-Range", "")
            match = re.fullmatch(r"bytes 0-0/(\d+)", content_range)
            if response.status != 206 or not match or int(match.group(1)) != int(row["size"]):
                raise RuntimeError(f"remote size mismatch: {row['file']} {content_range}")
        print(f"[{index}/{len(rows)}] ok {row['file']}")

    print(f"verified version={manifest['version']} objects={len(rows)}")


if __name__ == "__main__":
    main()
