"""Summarize balance-harness output (JSON lines from sim/runner.gd).

usage: python tools/analyze.py sim/out/*.jsonl [--by meta]
"""
import json
import sys
import glob
import statistics as st
from collections import Counter, defaultdict


def pct(xs, p):
    if not xs:
        return 0
    xs = sorted(xs)
    k = max(0, min(len(xs) - 1, int(round(p / 100 * (len(xs) - 1)))))
    return xs[k]


def main():
    files = []
    group_key = "persona"
    args = sys.argv[1:]
    if "--by" in args:
        i = args.index("--by")
        group_key = args[i + 1]
        del args[i:i + 2]
    for a in args:
        files.extend(glob.glob(a))
    rows = []
    for f in files:
        with open(f, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if line.startswith("{"):
                    rows.append(json.loads(line))
    groups = defaultdict(list)
    for r in rows:
        key = r.get(group_key, "?") if group_key != "persona+meta" else f"{r['persona']}/{r['meta']}"
        groups[key].append(r)

    hdr = f"{'group':<16}{'n':>4} {'dead':>5} {'ret':>5} {'win':>5} {'loops(p10/med/p90)':>20} {'bank':>6} {'bank/min':>8} {'bossR':>6} {'bossW':>6} {'time':>6}"
    print(hdr)
    print("-" * len(hdr))
    for key in sorted(groups):
        g = groups[key]
        n = len(g)
        dead = sum(1 for r in g if r["state"] == "dead") / n
        ret = sum(1 for r in g if r["state"] == "returned") / n
        win = sum(1 for r in g if r["state"] == "victory") / n
        loops = [r["loops"] for r in g]
        bank = [r["scrap"] for r in g]
        bpm = [r["scrap"] / max(1.0, r["time"] / 60.0) for r in g]
        boss_r = sum(1 for r in g if r["boss_loop"] > 0) / n
        boss_w = sum(1 for r in g if r["boss_result"] == "win") / max(1, sum(1 for r in g if r["boss_loop"] > 0))
        tm = st.mean(r["time"] for r in g) / 60.0
        print(f"{key:<16}{n:>4} {dead:>5.0%} {ret:>5.0%} {win:>5.0%} "
              f"{pct(loops,10):>6}/{st.median(loops):>5}/{pct(loops,90):>5}   {st.mean(bank):>6.0f} {st.mean(bpm):>8.1f} "
              f"{boss_r:>6.0%} {boss_w:>6.0%} {tm:>5.1f}m")

    print()
    for key in sorted(groups):
        g = groups[key]
        causes = Counter(r["death_cause"] for r in g if r["state"] == "dead")
        placed = Counter()
        evolved = Counter()
        cars = Counter()
        picks = Counter()
        for r in g:
            placed.update(r.get("placed", {}))
            evolved.update(r.get("evolved", {}))
            cars.update(r.get("cars", []))
            picks.update(r.get("depot_picks", {}))
        boss_loops = [r["boss_loop"] for r in g if r["boss_loop"] > 0]
        boss_hp = [r["boss_hp"] for r in g if r["boss_loop"] > 0 and r["boss_result"] != "win"]
        dmg = defaultdict(list)
        for r in g:
            for i, d in enumerate(r.get("dmg_by_loop", [])):
                dmg[i + 1].append(d)
        hull_end = [r["hull_end"] for r in g if r["state"] != "dead"]
        print(f"[{key}] deaths: {dict(causes.most_common(5))}")
        print(f"   placed: {dict(placed.most_common(9))}")
        print(f"   evolved: {dict(evolved.most_common(8))}  corrupted/run: {st.mean(r['corrupted'] for r in g):.2f}")
        print(f"   cars: {dict(cars.most_common(8))}  picks: {dict(picks)}")
        if boss_loops:
            bt = [r.get("boss_time", 0) for r in g if r["boss_loop"] > 0]
            print(f"   boss loop med {st.median(boss_loops)}  boss hp left (losses) med {st.median(boss_hp) if boss_hp else '-'}"
                  f"  fight time med {st.median(bt):.0f}s")
        dl = "  ".join(f"L{k}:{st.mean(v):.0f}" for k, v in sorted(dmg.items())[:14])
        print(f"   dmg/loop: {dl}")
        print(f"   kills/run {st.mean(r['kills'] for r in g):.0f}  cards/run {st.mean(r['cards_drawn'] for r in g):.1f}  "
              f"discarded {st.mean(r['discarded'] for r in g):.1f}  starved {st.mean(r['starved'] for r in g):.1f}  "
              f"survivors(end) {st.mean(r['survivors_end'] for r in g):.1f}  relics {st.mean(len(r['relics']) for r in g):.1f}  "
              f"hull_end(alive) {st.mean(hull_end) if hull_end else 0:.2f}")
        print()


def card_report(rows):
    """Within-persona comparison: runs that placed a card type >= 2 times vs runs that placed it <= 1.
    Big positive gaps suggest a dominant pick, big negative gaps a trap."""
    types = sorted({k for r in rows for k in r.get("placed", {})})
    print(f"{'card':<12}{'n_hi':>6}{'dBank':>8}{'dLoops':>8}{'dWin':>7}")
    for tp in types:
        d_bank, d_loop, d_win, n_hi = [], [], [], 0
        by = defaultdict(list)
        for r in rows:
            by[(r["persona"], r.get("meta", ""))].append(r)
        for p, g in by.items():
            hi = [r for r in g if r.get("placed", {}).get(tp, 0) >= 2]
            lo = [r for r in g if r.get("placed", {}).get(tp, 0) <= 1]
            if len(hi) >= 4 and len(lo) >= 4:
                n_hi += len(hi)
                d_bank.append(st.mean(r["scrap"] for r in hi) - st.mean(r["scrap"] for r in lo))
                d_loop.append(st.mean(r["loops"] for r in hi) - st.mean(r["loops"] for r in lo))
                d_win.append(st.mean(r["state"] == "victory" for r in hi) - st.mean(r["state"] == "victory" for r in lo))
        if d_bank:
            print(f"{tp:<12}{n_hi:>6}{st.mean(d_bank):>8.0f}{st.mean(d_loop):>8.2f}{st.mean(d_win):>7.0%}")


if __name__ == "__main__":
    if "--cards" in sys.argv:
        sys.argv.remove("--cards")
        rows = []
        for a in sys.argv[1:]:
            for f in glob.glob(a):
                with open(f, encoding="utf-8") as fh:
                    rows += [json.loads(l) for l in fh if l.strip().startswith("{")]
        card_report(rows)
    else:
        main()
