#!/usr/bin/env bash
# The AI tuning bench (tests/bench/ai) offline: the task file is well formed, the
# checks read a thread the way headless.sh writes it (compacted calls included),
# a candidate harness is refused for growth, dropped placeholders, files off the
# surface and leaked answers, and an improver session edits only its copy.
# No model and no compositor: the rollouts themselves are what the bench runs.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
command -v python3 > /dev/null || { echo "skip: python3 not installed"; exit 0; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

python3 -I - "$REPO_ROOT/tests/bench/ai" "$tmp" <<'PY'
import json, shutil, sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import run, tune

tmp = Path(sys.argv[2])
failed = []
def expect(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failed.append(what)

# --- the task file
tasks = run.load_tasks()
ids = [t["id"] for t in tasks]
expect(len(ids) == len(set(ids)), "task ids are unique")
tune_n, held_n = len(run.load_tasks("tune")), len(run.load_tasks("held"))
expect(tune_n >= 2 * held_n - 1 and held_n > 0, f"about two thirds tune ({tune_n}) to one third held ({held_n})")
known = {"called", "called_any", "not_called", "final", "final_not", "final_max", "no_emoji", "config"}
expect(all(set(c) - {"args"} <= known for t in tasks for c in t["checks"]), "every check is a known kind")
expect(all(t["goal"] and t["turns"] for t in tasks), "every task has a goal and turns")
leaks = json.loads(run.TASKS.read_text())["leaks"]
stubbed = " ".join(v for t in tasks for v in t.get("stubs", {}).values())
expect(all(w in stubbed or any(w in u for t in tasks for u in t["turns"]) for w in leaks),
       "every leak word comes from a stub or a turn")

# --- checks on a thread shaped like headless.sh output, with one call compacted away
out = {
    "ok": True,
    "messages": [
        {"role": "user", "content": "Move my bar"},
        {"role": "assistant", "content": "", "functionCall": {"name": "set_shell_config", "args": {"key": "bar.bottom", "value": "true"}}},
        {"role": "tool", "content": "Set `bar.bottom` to `true`."},
        {"role": "assistant", "content": "<think>x</think>Done, your bar is at the **bottom** now."},
    ],
    "requests": [
        {"body": {"messages": [{"role": "system", "content": "s"}, {"role": "user", "content": "Move my bar"}],
                  "tools": [{"type": "function", "function": {"name": "get_shell_config"}}]}},
        {"body": {"messages": [{"role": "system", "content": "s"}, {"role": "user", "content": "Move my bar"},
                               {"role": "assistant", "content": "", "tool_calls": [{"id": "1", "type": "function",
                                "function": {"name": "get_shell_config", "arguments": "{}"}}]},
                               {"role": "tool", "content": "{...}", "tool_call_id": "1"}]}},
    ],
}
config = {"bar": {"bottom": True}}
names = [n for n, _ in run.calls(out)]
expect(names == ["get_shell_config", "set_shell_config"], f"calls include the compacted one, in order: {names}")
expect(run.check({"called": "set_shell_config", "args": {"key": "^bar\\.bottom$"}}, out, config)[0], "called with args")
expect(not run.check({"called": "set_shell_config", "args": {"key": "^bar\\.top$"}}, out, config)[0], "called with wrong args fails")
expect(not run.check({"not_called": "*"}, out, config)[0], "not_called * fails when a tool ran")
expect(run.check({"final": "bottom"}, out, config)[0], "final reads the last answer")
expect(not run.check({"final": "think|x</"}, out, config)[0], "final ignores <think>")
expect(run.check({"config": {"bar.bottom": True}}, out, config)[0], "config check")
expect(run.check({"config": {"bar.bottom": "true"}}, out, config)[0], "config check accepts a string true")
expect(not run.check({"config": {"bar.bottom": False}}, out, config)[0], "config check fails on a wrong value")
expect(not run.check({"no_emoji": True}, {"messages": [{"role": "assistant", "content": "hi \U0001F600"}]}, {})[0], "emoji found")
expect(run.check({"final": "{KERNEL}"}, {"messages": [{"role": "assistant", "content": f"kernel {run.facts()['{KERNEL}']}"}]}, {})[0],
       "placeholders are filled in checks")
traj = run.trajectory({"id": "t", "goal": "g"}, out, [(True, "")])
expect("[ACTION] get_shell_config {}" in traj and "[REQUEST 1] tools offered: get_shell_config" in traj
       and "[OUTCOME] met the goal" in traj, "trajectory shows requests, actions and outcome")

# --- validation
base = tmp / "base"
shutil.copytree(tune.SECTIONS, base / "system")
budget = tune.sections_size(base)
def cand(name, edit):
    c = tmp / name
    shutil.copytree(base, c)
    edit(c)
    return tune.validate(c, base, budget)
expect(cand("same", lambda c: None) == "", "an unchanged harness is valid")
expect("over" in cand("big", lambda c: (c / "system/40-style.md").write_text((c / "system/40-style.md").read_text() + "x" * 50)),
       "growth past the budget is refused")
expect("placeholders" in cand("ph", lambda c: (c / "system/10-machine.md").write_text("## Machine\n- nothing\n")),
       "a dropped placeholder is refused")
expect("off the surface" in cand("extra", lambda c: (c / "skills").mkdir() or (c / "skills/x.md").write_text("x")),
       "a file off the surface is refused")
def leak(c):
    p = c / "system/40-style.md"
    p.write_text(p.read_text()[:-40] + "\n- The E13 costs US$369.\n")
expect("answers" in cand("leak", leak), "a task answer in the harness is refused")

# --- an improver session edits only its own copy
class A: pass
evidence = tmp / "rollouts"
(evidence / "t" / "0").mkdir(parents=True)
(evidence / "t" / "0" / "trajectory.md").write_text("# t\n[OUTCOME] did not meet the goal\n")
out_dir = tmp / "run"
fake = "sh -c 'sed -i \"s/Casual, brief/Brief/\" harness/system/40-style.md; ls evidence > NOTES.md'"
h = tune.improve("inv1", "mission", base, evidence, out_dir, fake, budget)
expect(h is not None and "Brief, straight" in (h / "system/40-style.md").read_text(), "the improver's edit is the candidate")
expect("Casual, brief" in (base / "system/40-style.md").read_text(), "the base is untouched")
expect((h / "NOTES.md").read_text().strip() == "00-t-0.md", "evidence reached the workspace, and notes came back")
bad = "sh -c 'echo x > harness/system/99-new.md; mkdir harness/skills; echo y > harness/skills/a.md'"
expect(tune.improve("inv2", "mission", base, evidence, out_dir, bad, budget) is None, "an off-surface edit is rejected")

sys.exit(1 if failed else 0)
PY
