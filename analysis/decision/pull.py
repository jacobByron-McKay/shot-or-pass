"""Every shot, with its event freeze frame, for the decision score.

  python analysis/decision/pull.py women   every women's competition in the open data
  python analysis/decision/pull.py men     Premier League and La Liga 2015/16, Leverkusen 2023/24

With no argument it pulls both. Writes data-raw/ext/women_shots.jsonl and
data-raw/ext/men_shots.jsonl, one shot per line. Event files are read and
thrown away, so only the shots stay on disk (about 65 and 40 MB), but every
match is downloaded once: allow a while for the women's 1,300 or so. Run it
from the repository root.
"""
import json
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

RAW = "https://raw.githubusercontent.com/statsbomb/open-data/master/data"
OUT = Path("data-raw/ext")

# competition and season ids: the two complete 2015/16 seasons, and the 34
# Leverkusen matches from 2023/24
MEN = {(2, 27), (11, 27), (9, 281)}


def get(url):
    for attempt in range(5):
        try:
            with urllib.request.urlopen(url, timeout=120) as r:
                return json.loads(r.read().decode("utf-8"))
        except Exception:
            if attempt == 4:
                raise


def name(d):
    return d["name"] if isinstance(d, dict) else None


def shots_from(match, comp):
    events = get(f"{RAW}/events/{match['match_id']}.json")
    rows = []
    for e in events:
        if name(e.get("type")) != "Shot":
            continue
        s = e["shot"]
        rows.append({
            "competition": comp["competition_name"],
            "season": comp["season_name"],
            "match_id": match["match_id"],
            "shot_id": e["id"],
            "player": name(e.get("player")),
            "player_id": (e.get("player") or {}).get("id"),
            "team": name(e.get("team")),
            "position": name(e.get("position")),
            "minute": e.get("minute"),
            "x": e["location"][0], "y": e["location"][1],
            "end": s.get("end_location"),
            "xg": s.get("statsbomb_xg"),
            "outcome": name(s.get("outcome")),
            "shot_type": name(s.get("type")),
            "body_part": name(s.get("body_part")),
            "technique": name(s.get("technique")),
            "first_time": bool(s.get("first_time")),
            "under_pressure": bool(e.get("under_pressure")),
            "play_pattern": name(e.get("play_pattern")),
            "freeze_frame": [
                {"x": p["location"][0], "y": p["location"][1],
                 "teammate": p["teammate"], "player": name(p.get("player")),
                 "position": name(p.get("position"))}
                for p in s.get("freeze_frame", [])
            ],
        })
    return rows


def pull(which, comps):
    if which == "women":
        comps = [c for c in comps if c["competition_gender"] == "female"]
    else:
        comps = [c for c in comps if (c["competition_id"], c["season_id"]) in MEN]
    jobs = [(m, c) for c in comps
            for m in get(f"{RAW}/matches/{c['competition_id']}/{c['season_id']}.json")]
    print(which, "matches:", len(jobs), flush=True)
    n = 0
    dest = OUT / f"{which}_shots.jsonl"
    part = dest.with_suffix(".part")
    with open(part, "w", encoding="utf-8") as f, ThreadPoolExecutor(16) as pool:
        for i, rows in enumerate(pool.map(lambda j: shots_from(*j), jobs), 1):
            for r in rows:
                f.write(json.dumps(r) + "\n")
            n += len(rows)
            if i % 100 == 0:
                print(i, "matches,", n, "shots", flush=True)
    part.replace(dest)
    print(dest, n, "shots", flush=True)


def main():
    which = sys.argv[1:] or ["women", "men"]
    OUT.mkdir(parents=True, exist_ok=True)
    comps = get(f"{RAW}/competitions.json")
    for w in which:
        pull(w, comps)


if __name__ == "__main__":
    main()
