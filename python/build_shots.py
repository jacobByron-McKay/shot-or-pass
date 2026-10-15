"""Build the shot table from raw StatsBomb files and cache it.

The Python counterpart of analysis/01-build-shots.R. Run this first.
"""
import time

from shotorpass.features import build_shots
from shotorpass.statsbomb import ROOT, fetch_all, sb_matches, sb_path

CACHE = ROOT / "cache" / "shots_py.pkl"


def main():
    ids = [m["match_id"] for m in sb_matches()]
    print("matches in the tournament:", len(ids))

    if not sb_path("events", f"{ids[0]}.json").exists():
        print("raw data not found, fetching")
        fetch_all()

    t0 = time.perf_counter()
    shots = build_shots(ids)
    elapsed = time.perf_counter() - t0

    n_opts = shots["options"].map(len)
    print("shots:", len(shots))
    print(f"with at least one forward option: {100 * (n_opts > 0).mean():.1f}%")
    print("mean options per shot:", round(n_opts.mean(), 2))
    print(f"median forward visibility: {100 * shots['forward_visible'].median():.1f}%")

    CACHE.parent.mkdir(exist_ok=True)
    shots.to_pickle(CACHE)
    print(f"written to cache/{CACHE.name}")
    print(f"build time: {elapsed:.1f} s")


if __name__ == "__main__":
    main()
