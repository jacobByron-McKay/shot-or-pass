"""Compile, run and merge the boba version of the 96, then check it against
what run_multiverse.py wrote.

    ../scratch/boba-venv/Scripts/python boba/run_boba.py            # from python/
    ../scratch/boba-venv/Scripts/python boba/run_boba.py --jobs 0   # every core

Run it with the interpreter boba is installed in. Everything boba writes goes
to scratch/boba-out/, which is not committed.

By hand it is three commands, with the full path to python/ on PYTHONPATH so
the universes can import the package. From the repository root:

    boba compile --script python/boba/template.py --out scratch/boba-out
    cd scratch/boba-out
    boba run --all
    boba merge result_{}.csv

This does the same, plus four things boba leaves to you: it runs the
universes in this interpreter's environment, keeps each universe's number the
same from one compile to the next, keeps 20 universes at once within memory,
and fails when a universe did.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd

TEMPLATE = Path(__file__).resolve().parent / "template.py"
PYTHON_DIR = TEMPLATE.parents[1]
ROOT = TEMPLATE.parents[2]
OUT = ROOT / "scratch" / "boba-out"
MULTIVERSE = OUT / "multiverse"
REFERENCE = ROOT / "reports" / "specification-curve-v2-py.csv"
DECISIONS = ["option_pool", "completion", "receiver_context", "margin", "corners"]
TOLERANCE = 1e-9
timings = {}


def boba(*args, env=None):
    exe = shutil.which("boba", path=str(Path(sys.executable).parent))
    if exe is None:
        sys.exit(f"boba is not installed alongside {sys.executable}")
    t0 = time.perf_counter()
    subprocess.run([exe, *args], check=True, env=env)
    timings[f"boba {args[0]}"] = time.perf_counter() - t0


def pin_interpreter():
    """Point boba at this interpreter for running the universes.

    boba starts each universe with the command in multiverse/lang.json, which
    is a bare "python". On Windows that name is looked up next to the running
    interpreter before PATH, and a venv's python.exe hands over to the base
    install, so the universes ran outside the venv even with it activated. A
    relative path is no better: Windows resolves it from somewhere else, the
    universe never starts, and boba says nothing. An absolute path works.
    """
    lang = MULTIVERSE / "lang.json"
    langs = json.loads(lang.read_text())
    langs["python"]["run"] = [sys.executable, "{{script_name}}"]
    lang.write_text(json.dumps(langs))


def check_logs():
    """boba run exits 0 whatever happened to the universes, so look.

    It keeps each universe's exit code in boba_logs/logs.csv, and anything a
    universe wrote to stderr in error_<n>.txt. A universe that never started
    is in neither, so the count matters too.
    """
    n = len(pd.read_csv(MULTIVERSE / "summary.csv"))
    logs = pd.read_csv(MULTIVERSE / "boba_logs" / "logs.csv")
    failed = sorted(logs.loc[logs["exit_code"] != 0, "uid"])
    errors = sorted((MULTIVERSE / "boba_logs").glob("error_*.txt"))
    if len(logs) != n or failed or errors:
        sys.exit(f"{len(logs)} of {n} universes finished; failed: {failed or 'none'}; "
                 f"wrote to stderr: {[e.name for e in errors] or 'none'}")


def specification_curve():
    """boba's merged results beside the choices each universe made.

    merged.csv has a universe number and what the universe wrote, and
    summary.csv has the choices behind each universe file. Read as text, so
    "360" stays a name and not a number.
    """
    merged = pd.read_csv(MULTIVERSE / "merged.csv", float_precision="round_trip")
    summary = pd.read_csv(MULTIVERSE / "summary.csv", dtype=str)
    summary["uid"] = summary["Filename"].str.extract(r"universe_(\d+)", expand=False).astype(int)
    mv = summary.merge(merged, on="uid", validate="one_to_one")
    return mv[DECISIONS + ["shoot_was_right", "mean_edge"]].sort_values(DECISIONS)


def main():
    parser = argparse.ArgumentParser(description="The 96 after the fixes, through boba.")
    parser.add_argument("--jobs", type=int, default=1,
                        help="universes running at once, 0 for one per core (boba's --jobs)")
    args = parser.parse_args()

    OUT.mkdir(parents=True, exist_ok=True)
    started = time.perf_counter()
    # boba keeps the graph in sets, so which option pool gets which universe
    # numbers follows Python's string hashing and changes from one compile to
    # the next. A fixed seed keeps universe_17 the same universe every time.
    boba("compile", "--script", str(TEMPLATE), "--out", str(OUT),
         env={**os.environ, "PYTHONHASHSEED": "0"})
    pin_interpreter()
    # One OpenBLAS thread per universe. The parallelism is the universes
    # running side by side, and numpy's default of a thread per core had
    # each process reserve 1.4 GB, which ran Windows out of commit at 20 jobs.
    path = os.pathsep.join(p for p in [str(PYTHON_DIR), os.environ.get("PYTHONPATH")] if p)
    boba("run", "--all", "--dir", str(MULTIVERSE), "--jobs", str(args.jobs),
         env={**os.environ, "PYTHONPATH": path, "OPENBLAS_NUM_THREADS": "1"})
    check_logs()
    boba("merge", "result_{}.csv", "--base", str(MULTIVERSE / "results"),
         "--out", str(MULTIVERSE / "merged.csv"))
    timings["all three"] = time.perf_counter() - started

    mv = specification_curve()
    mv.to_csv(OUT / "specification-curve-v2-boba.csv", index=False)

    ref = pd.read_csv(REFERENCE, float_precision="round_trip", dtype={"receiver_context": str})
    both = ref.merge(mv, on=DECISIONS, how="outer", suffixes=("_ref", "_boba"), indicator=True)
    unmatched = both[both["_merge"] != "both"]
    if len(unmatched):
        sys.exit(f"{len(unmatched)} specifications are in only one of the two:\n{unmatched}")

    print(f"\n{len(both)} specifications matched to {REFERENCE.name} on the five choices")
    gaps = {}
    for c in ["shoot_was_right", "mean_edge"]:
        gaps[c] = np.max(np.abs(both[f"{c}_boba"] - both[f"{c}_ref"]))
        print(f"  largest difference in {c}: {gaps[c]:.3g}")
    swr = mv["shoot_was_right"]
    print(f"  shooting was right on {swr.min():.1f}% to {swr.max():.1f}% of shots "
          f"(run_multiverse.py: {ref['shoot_was_right'].min():.1f}% to "
          f"{ref['shoot_was_right'].max():.1f}%)")
    if max(gaps.values()) > TOLERANCE:
        sys.exit(f"boba's results differ from run_multiverse.py's by more than {TOLERANCE}")

    print(f"\nwall-clock time with --jobs {args.jobs}"
          f"{' (one per core)' if args.jobs == 0 else ''}")
    for label, secs in timings.items():
        print(f"  {label:<16}{secs:6.1f} s")
    print(f"\nwritten to {OUT.relative_to(ROOT).as_posix()}/")


if __name__ == "__main__":
    main()
