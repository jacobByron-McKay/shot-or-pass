"""Reading StatsBomb open data off disk, and fetching it if it is not there.

Data source: StatsBomb open data, https://github.com/statsbomb/open-data
Nothing is committed to this repository. See README for the licence terms.
"""
import json
import urllib.request
from pathlib import Path

import numpy as np

SB_RAW = "https://raw.githubusercontent.com/statsbomb/open-data/master/data"

# Competition 72 season 107 is the 2023 FIFA Women's World Cup, the most
# recent tournament in the open data with complete 360 coverage.
WWC_2023 = {"competition_id": 72, "season_id": 107}

ROOT = Path(__file__).resolve().parents[2]


def sb_path(*parts):
    return ROOT.joinpath("data-raw", *parts)


def download_json(url, dest):
    dest.parent.mkdir(parents=True, exist_ok=True)
    urllib.request.urlretrieve(url, dest)
    return dest


def read_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def sb_matches(comp=WWC_2023):
    """Match list for the tournament, downloading it on first use."""
    dest = sb_path("matches.json")
    if not dest.exists():
        download_json(f"{SB_RAW}/matches/{comp['competition_id']}/{comp['season_id']}.json", dest)
    return read_json(dest)


def sb_events(match_id):
    """Events for one match."""
    dest = sb_path("events", f"{match_id}.json")
    if not dest.exists():
        download_json(f"{SB_RAW}/events/{match_id}.json", dest)
    return read_json(dest)


def sb_frames(match_id):
    """Freeze frames for one match, keyed by the event id they belong to.

    Each frame holds the positions of the players the broadcast camera could
    see, flagged as teammate or opponent relative to the player on the ball.
    There are no player identities in a frame, only those flags.
    """
    dest = sb_path("three-sixty", f"{match_id}.json")
    if not dest.exists():
        download_json(f"{SB_RAW}/three-sixty/{match_id}.json", dest)
    frames = {}
    for f in read_json(dest):
        frames.setdefault(f["event_uuid"], f)
    return frames


def fetch_all(comp=WWC_2023):
    """Fetch everything the analysis needs. Roughly 500 MB and a few minutes."""
    ids = [m["match_id"] for m in sb_matches(comp)]
    for i, match_id in enumerate(ids, 1):
        sb_events(match_id)
        sb_frames(match_id)
        print(f"\r{i}/{len(ids)} matches", end="")
    print()
    return ids


def visible_polygon(frame):
    """The visible area polygon as an (n, 2) array.

    StatsBomb store it as a flat list of alternating x and y values.
    """
    v = frame.get("visible_area") or []
    if len(v) < 6:
        return np.empty((0, 2))
    return np.asarray(v, dtype=float).reshape(-1, 2)
