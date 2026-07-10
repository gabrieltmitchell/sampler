#!/usr/bin/env python3
"""Archive GitHub clone traffic into a cumulative history plus a Shields badge.

GitHub's traffic API only keeps 14 days of data, so this runs daily (via the
"Track downloads" workflow) and merges the latest window into clones.json on
the `traffic` branch. badge.json is a Shields.io endpoint payload rendered by
the downloads badge in the README.
"""

import json
import os
import urllib.request
from pathlib import Path

REPO = os.environ["REPO"]
TOKEN = os.environ["GH_TOKEN"]
DATA_DIR = Path(os.environ.get("DATA_DIR", "."))


def fetch_clones() -> dict:
    request = urllib.request.Request(
        f"https://api.github.com/repos/{REPO}/traffic/clones",
        headers={
            "Authorization": f"Bearer {TOKEN}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    with urllib.request.urlopen(request) as response:
        return json.load(response)


def abbreviate(value: int) -> str:
    if value >= 1_000_000:
        return f"{value / 1_000_000:.1f}M"
    if value >= 1_000:
        return f"{value / 1_000:.1f}k"
    return str(value)


def main() -> None:
    history_path = DATA_DIR / "clones.json"
    badge_path = DATA_DIR / "badge.json"

    days: dict[str, dict[str, int]] = {}
    if history_path.exists():
        days = json.loads(history_path.read_text())["days"]

    # The newest API window is authoritative for the days it covers; partial
    # counts for "today" get corrected by tomorrow's run.
    for day in fetch_clones().get("clones", []):
        date = day["timestamp"][:10]
        days[date] = {"count": day["count"], "uniques": day["uniques"]}

    total_clones = sum(day["count"] for day in days.values())
    unique_days = sum(day["uniques"] for day in days.values())

    history_path.write_text(
        json.dumps({"days": dict(sorted(days.items()))}, indent=2) + "\n"
    )
    badge_path.write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "label": "downloads",
                "message": f"{abbreviate(total_clones)} total",
                "color": "brightgreen",
            }
        )
        + "\n"
    )
    print(
        f"{REPO}: {total_clones} clones total "
        f"({unique_days} unique-cloner-days) across {len(days)} recorded days"
    )


if __name__ == "__main__":
    main()
