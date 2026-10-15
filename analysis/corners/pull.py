"""Corners won, and the xG that came from them, for every team in every women's
match in the open data, with both starting elevens.

Writes data-raw/ext/women_corners.csv, one row per team per match, which
analysis/corners/ratings.R turns into the team corner ratings. Run it from the
repository root. It reads every women's match, so it takes a while.
"""
import csv
import json
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

RAW = "https://raw.githubusercontent.com/statsbomb/open-data/master/data"
OUT = Path("data-raw/ext/women_corners.csv")


def get(url):
    for attempt in range(5):
        try:
            with urllib.request.urlopen(url, timeout=180) as r:
                return json.loads(r.read().decode("utf-8"))
        except Exception:
            if attempt == 4:
                raise


def one_match(m, c):
    mid = m["match_id"]
    ev = get(f"{RAW}/events/{mid}.json")
    lineups = get(f"{RAW}/lineups/{mid}.json")

    # a corner's possession counts from its first event, so a shot three passes
    # later still belongs to the corner
    poss_first = {}
    for e in ev:
        poss_first.setdefault(e["possession"], e)
    corner = {}
    for e in ev:
        first = poss_first[e["possession"]]
        if first.get("play_pattern", {}).get("name") != "From Corner":
            continue
        pt = first["possession_team"]["name"]
        rec = corner.setdefault(pt, {"poss": set(), "xg": 0.0})
        rec["poss"].add(e["possession"])
        if (e["type"]["name"] == "Shot" and e["team"]["name"] == pt
                and e["shot"]["type"]["name"] != "Penalty"):
            rec["xg"] += e["shot"].get("statsbomb_xg", 0.0)

    teams = [t["team_name"] for t in lineups]
    starters = {t["team_name"]: [p["player_id"] for p in t["lineup"]
                                 if any(pos.get("start_reason") == "Starting XI"
                                        for pos in p.get("positions", []))]
                for t in lineups}
    rows = []
    for t in teams:
        opp = [o for o in teams if o != t]
        rec = corner.get(t, {"poss": set(), "xg": 0.0})
        rows.append({"match_id": mid, "date": m["match_date"], "competition": c["competition_name"],
                     "season": c["season_name"], "team": t, "opponent": opp[0] if opp else "",
                     "corners": len(rec["poss"]), "corner_xg": rec["xg"],
                     "xi": " ".join(str(p) for p in starters.get(t, [])),
                     "opp_xi": " ".join(str(p) for p in starters.get(opp[0], [])) if opp else ""})
    return rows


def main():
    comps = [c for c in get(f"{RAW}/competitions.json") if c["competition_gender"] == "female"]
    jobs = [(m, c) for c in comps
            for m in get(f"{RAW}/matches/{c['competition_id']}/{c['season_id']}.json")]
    print("matches:", len(jobs), flush=True)
    rows = []
    with ThreadPoolExecutor(12) as pool:
        for i, r in enumerate(pool.map(lambda j: one_match(*j), jobs), 1):
            rows += r
            if i % 100 == 0:
                print(i, "matches", flush=True)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    print(OUT, len(rows), "rows", flush=True)


if __name__ == "__main__":
    main()
