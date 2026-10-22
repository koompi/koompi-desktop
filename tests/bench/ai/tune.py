#!/usr/bin/env python3
"""Tune the AI's prompt sections on the task set: Propose, Probe, Compose.

    uv run tests/bench/ai/tune.py --out RUNDIR [--k 1] [--mode agg|seq] [--repeat 2]
                                  [--model gemma4-e4b] [--improver CMD]

The method is Harness² (github.com/google-research/harness2, Apache-2.0), ported to
this agent's surface rather than imported: Harness² edits a coding agent's skills,
subagents and plugins, and this agent has none of those. What it can change is the
five always-on section files, every byte of them paid on a 16k-window model.

  base     probe the shipped sections on the tune split
  propose  two improvers read the trajectories: INV fixes how the agent works (tools,
           order, failures), DOM fixes what it knows. Each edits its own copy.
  probe    each candidate runs the tune split
  compose  an improver reads the candidates, their notes and their trajectories and
           writes one set (agg: k composers from one pool; seq: k rounds, each
           building on the last)
  adopt    the best candidate by tune passes, then smallest, runs the held split
           beside the base. report.md says ADOPT only if held passes rise, no tune
           task loses passes, and the sections are no larger. Nothing is installed.

The improver is `claude -p` in a workspace that holds only copies and evidence, with
edit tools and no shell. --improver replaces it: CMD runs in the workspace with the
mission on stdin, which is how the loop is tested without a model.
"""
import argparse
import json
import re
import shlex
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run as bench  # noqa: E402

SECTIONS = bench.REPO / "dots/.config/quickshell/koompi/defaults/ai/prompts/system"
PLACEHOLDER = re.compile(r"\{[A-Z]+\}")
CLAUDE = ["claude", "-p", "--output-format", "json", "--permission-mode", "acceptEdits",
          "--allowedTools", "Read", "Edit", "Write", "Glob", "Grep",
          "--disallowedTools", "Bash", "WebFetch", "WebSearch", "Agent"]

COMMON = """\
# The agent

{AINAME} is the assistant built into KOOMPI OS, a Linux desktop. It runs on the owner's laptop on
gemma4-e4b: a small local model, a 16k-token window, about 14 tokens a second, temperature 0.5.
Each turn it sees the system prompt, the conversation and a few tool declarations: as many as fit
1461 bytes, picked by keyword overlap with the user's message.

The system prompt is the files in `harness/system/`, joined in file-name order. A `{{NAME}}` in
them is filled in at run time (the machine facts, the owner's name, memories); keep every one
that is there. Nothing else of the harness is yours to change in this session.

# The evidence

`evidence/` holds one trajectory per task run with the current harness: the goal, what the user
said, every request with the tools it offered, the model's actions and what came back, and
whether the goal was met. Tools that would leave the machine answered with fixed text.

# The rules

- Change only what a trajectory shows needs changing. In `NOTES.md`, for each change, name the
  trajectory and the line that motivates it. A change you cannot tie to a moment is noise.
- The sections together stay at or under {budget} bytes (they are {size} now). If you add, cut.
- This model follows short, concrete, imperative lines best. One rule per line; an example beats
  an explanation; say what to do rather than what not to do.
- Never write a task's answer, product, price, name or number into the harness: the next owner
  asks about something else. Write how to find answers, not the answers.
- A tool missing from a request was not offered that turn; prose cannot call it. Say so in
  `NOTES.md` instead of writing rules for it.
"""

INV = """\
# Your part: how the agent works

You own procedure: which tool for which question, in what order, what to do when a call fails
or the owner declines, when to answer from the system prompt with no tool, and when to stop.
Find the earliest moment each failing trajectory went wrong and fix that moment.
Leave subject matter and facts to a parallel improver.
"""

DOM = """\
# Your part: what the agent knows

You own the knowledge the agent lacks: who it is, what the machine section already answers,
how the KOOMPI desktop and its settings are organised, what a good answer contains for each
kind of question. Turn it into checkable lines the model can apply.
Leave tool procedure and ordering to a parallel improver.
"""

COMPOSE = """\
# Your part: compose

`candidates/` holds {n} edited harnesses. Each has its `harness/`, the `NOTES.md` its improver
wrote, and `evidence/` from running it. `evidence/` at the top is the harness you start from.
Write one harness in `harness/` that keeps the changes whose trajectories improved and drops the
ones that did not help or broke something. Compare trajectories task by task before you decide.
In `NOTES.md`, say what you kept, from which candidate, and why.
"""


def sections_size(harness):
    return sum(len(p.read_bytes()) for p in (Path(harness) / "system").glob("*.md"))


def write_evidence(dest, rollouts):
    dest.mkdir(parents=True, exist_ok=True)
    failing_first = sorted(rollouts.glob("*/*/trajectory.md"),
                           key=lambda p: ("met the goal" in p.read_text().splitlines()[-1], str(p)))
    for i, src in enumerate(failing_first):
        shutil.copy(src, dest / f"{i:02d}-{src.parent.parent.name}-{src.parent.name}.md")


def improve(label, mission, harness, evidence, out, improver, budget, candidates=()):
    """One improver session in its own workspace; returns the new harness dir, or None."""
    ws = out / "work" / label
    shutil.rmtree(ws, ignore_errors=True)
    shutil.copytree(harness, ws / "harness")
    write_evidence(ws / "evidence", evidence)
    for name, (h, notes, ev) in candidates:
        shutil.copytree(h, ws / "candidates" / name / "harness")
        if notes.exists():
            shutil.copy(notes, ws / "candidates" / name / "NOTES.md")
        write_evidence(ws / "candidates" / name / "evidence", ev)
    (ws / "MISSION.md").write_text(mission)
    cmd = shlex.split(improver) if improver else CLAUDE
    with open(ws / "improver.log", "w") as log:
        p = subprocess.run(cmd, input=mission + "\nDo the work now: edit the files under harness/ and write NOTES.md.\n",
                           cwd=ws, stdout=log, stderr=subprocess.STDOUT, text=True, timeout=1800)
    dest = out / "harnesses" / label
    shutil.rmtree(dest, ignore_errors=True)
    shutil.copytree(ws / "harness", dest)
    if (ws / "NOTES.md").exists():
        shutil.copy(ws / "NOTES.md", dest / "NOTES.md")
    problem = validate(dest, harness, budget) if p.returncode == 0 else f"improver exited {p.returncode}"
    (dest / "VALID").write_text(problem or "ok\n")
    return None if problem else dest


def validate(candidate, base, budget):
    """Why a candidate cannot be used, or ''."""
    base_files = sorted(p.name for p in (Path(base) / "system").glob("*.md"))
    got = sorted(p.name for p in (candidate / "system").glob("*.md"))
    extra = [p.relative_to(candidate).as_posix() for p in candidate.rglob("*")
             if p.is_file() and p.parent != candidate / "system" and p.name not in ("NOTES.md", "VALID")]
    if extra:
        return f"files off the surface: {extra}"
    if not got:
        return "no sections left"
    size = sections_size(candidate)
    if size > budget:
        return f"sections are {size} bytes, over the {budget}-byte budget"
    want = set(PLACEHOLDER.findall("".join((Path(base) / "system" / n).read_text() for n in base_files)))
    have = set(PLACEHOLDER.findall("".join((candidate / "system" / n).read_text() for n in got)))
    if want - have:
        return f"placeholders dropped: {sorted(want - have)}"
    text = "".join((candidate / "system" / n).read_text() for n in got).lower()
    leaked = [w for w in json.loads(bench.TASKS.read_text()).get("leaks", []) if w.lower() in text]
    if leaked:
        return f"task answers written into the harness: {leaked}"
    return ""


def probe(label, harness, split, args, out):
    s = bench.run(Path(harness) / "system", out / "rollouts" / label / split, bench.load_tasks(split),
                  bench.model_spec(args.model), args.repeat, args.timeout,
                  log=lambda line: print(f"[{label}] {line}", flush=True))
    print(f"[{label}] {split}: {s['passed']}/{s['total']}", flush=True)
    return s


def mission(part, size, budget, **kw):
    return COMMON.format(AINAME="{AINAME}", size=size, budget=budget) + "\n" + part.format(**kw)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", required=True)
    ap.add_argument("--k", type=int, default=1)
    ap.add_argument("--mode", choices=["agg", "seq"], default="agg")
    ap.add_argument("--repeat", type=int, default=2)
    ap.add_argument("--model", default="gemma4-e4b")
    ap.add_argument("--timeout", type=int, default=180)
    ap.add_argument("--improver", default="", help="command run in the workspace instead of claude -p")
    ap.add_argument("--base", default="", help="a harness dir with system/, instead of the shipped sections")
    args = ap.parse_args()

    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    base = out / "harnesses" / "base"
    if not base.exists():
        shutil.copytree(Path(args.base) / "system" if args.base else SECTIONS, base / "system")
    budget = sections_size(base)

    trees, scores = {"base": base}, {"base": probe("base", base, "tune", args, out)}
    ev = lambda label: out / "rollouts" / label / "tune"
    notes = lambda label: trees[label] / "NOTES.md"

    # improvers run side by side; probes one at a time, because the local model is one engine
    def propose(label, part, harness, from_label):
        h = improve(label, mission(part, sections_size(harness), budget), harness, ev(from_label), out,
                    args.improver, budget)
        if not h:
            print(f"[{label}] rejected: {(out / 'harnesses' / label / 'VALID').read_text().strip()}", flush=True)
        return label, h

    def probe_all(made):
        for label, h in made:
            if h:
                trees[label] = h
                scores[label] = probe(label, h, "tune", args, out)
        return [label for label, h in made if h]

    def compose(label, pool, harness, from_label):
        cands = [(name, (trees[name], notes(name), ev(name))) for name in pool if name in trees]
        if not cands:
            return None
        made = improve(label, mission(COMPOSE, sections_size(harness), budget, n=len(cands)), harness,
                       ev(from_label), out, args.improver, budget, cands)
        return (probe_all([(label, made)]) or [None])[0]

    if args.mode == "agg":
        with ThreadPoolExecutor(2) as pool:
            labels = [f"{d}{i}" for i in range(1, args.k + 1) for d in ("inv", "dom")]
            made = probe_all(pool.map(lambda l: propose(l, INV if l.startswith("inv") else DOM, base, "base"), labels))
        for i in range(1, args.k + 1):
            compose(f"agg{i}", made, base, "base")
    else:
        current, cur_label, history = base, "base", []
        for t in range(1, args.k + 1):
            with ThreadPoolExecutor(2) as pool:
                made = probe_all(pool.map(lambda s: propose(f"{s[0]}{t}", s[1], current, cur_label),
                                          [("inv", INV), ("dom", DOM)]))
            history += made
            c = compose(f"c{t}", history, current, cur_label)
            if c:
                history.append(c)
                current, cur_label = trees[c], c

    ranked = sorted((l for l in scores if l != "base"),
                    key=lambda l: (-scores[l]["passed"], sections_size(trees[l])))
    report = [f"# Tuning run {out.name}", "", "| harness | tune passed | bytes |", "| --- | --- | --- |"]
    report += [f"| {l} | {scores[l]['passed']}/{scores[l]['total']} | {sections_size(trees[l])} |" for l in scores]
    if not ranked:
        report += ["", "No candidate survived validation. Keep the base."]
    else:
        best = ranked[0]
        held_base = probe("base", base, "held", args, out)
        held_best = probe(best, trees[best], "held", args, out)
        lost = [t for t, n in scores["base"]["tasks"].items() if scores[best]["tasks"].get(t, 0) < n]
        bigger = sections_size(trees[best]) > budget
        adopt = held_best["passed"] > held_base["passed"] and not lost and not bigger
        report += ["", f"Best: **{best}**. Held out: base {held_base['passed']}/{held_base['total']}, "
                       f"{best} {held_best['passed']}/{held_best['total']}.",
                   f"Tune tasks that lost passes: {', '.join(lost) or 'none'}.",
                   "", f"**{'ADOPT' if adopt else 'KEEP THE BASE'}**: "
                       + (f"copy `harnesses/{best}/system/*.md` over `defaults/ai/prompts/system/`." if adopt
                          else "the candidate did not clear held-out improvement, no regression and no growth.")]
    (out / "report.md").write_text("\n".join(report) + "\n")
    print("\n".join(report))


if __name__ == "__main__":
    main()
