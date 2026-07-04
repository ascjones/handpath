#!/usr/bin/env python3
"""Compare a session of watch IDDX readings against deWiz ground truth.

Usage: scripts/compare.py data/2026-07-04.csv [more.csv ...]

CSV columns (see data/TEMPLATE.csv):
  swing,club,swing_type,watch_iddx,dewiz_iddx,notes
  swing_type: full | partial | practice | none
  Leave watch_iddx / dewiz_iddx empty when that device recorded nothing.
"""
import csv
import statistics
import sys


def fnum(s):
    s = (s or "").strip()
    return float(s) if s else None


def summarize(label, pairs):
    diffs = [w - d for w, d in pairs]
    bias = statistics.mean(diffs)
    sd = statistics.stdev(diffs) if len(diffs) > 1 else float("nan")
    mae = statistics.mean(abs(x) for x in diffs)
    r = (statistics.correlation([w for w, _ in pairs], [d for _, d in pairs])
         if len(pairs) > 2 else float("nan"))
    print(f"  {label:8s} n={len(pairs):3d}  bias={bias:+6.1f}°  "
          f"sd={sd:5.1f}°  mae={mae:5.1f}°  r={r:5.2f}")


def main(paths):
    rows = []
    for path in paths:
        with open(path, newline="") as f:
            rows.extend(csv.DictReader(f))

    real = [r for r in rows if r["swing_type"] in ("full", "partial")]
    nonswings = [r for r in rows if r["swing_type"] in ("practice", "none")]

    paired = [(fnum(r["watch_iddx"]), fnum(r["dewiz_iddx"]), r) for r in real]
    both = [(w, d, r) for w, d, r in paired if w is not None and d is not None]
    missed = [r for w, _, r in paired if w is None]
    false_trig = [r for r in nonswings if fnum(r["watch_iddx"]) is not None]

    print(f"{len(rows)} rows: {len(real)} real swings "
          f"({len(both)} with both readings), {len(nonswings)} non-swings")
    print(f"missed swings: {len(missed)}   "
          f"false triggers: {len(false_trig)}/{len(nonswings)}")

    if len(both) < 2:
        print("not enough paired readings to compare")
        return

    print("\nwatch vs deWiz (watch - deWiz):")
    summarize("all", [(w, d) for w, d, _ in both])
    for club in sorted({r["club"] for _, _, r in both}):
        club_pairs = [(w, d) for w, d, r in both if r["club"] == club]
        if len(club_pairs) > 1:
            summarize(club, club_pairs)

    worst = sorted(both, key=lambda t: -abs(t[0] - t[1]))[:5]
    print("\nworst disagreements:")
    for w, d, r in worst:
        print(f"  swing {r['swing']:>3s} ({r['club']}): "
              f"watch {w:+.0f}° vs deWiz {d:+.0f}°  {r['notes']}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1:])
