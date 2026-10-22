#!/usr/bin/env python3
"""Run the AI task set against one prompt set and score it with deterministic checks.

    uv run tests/bench/ai/run.py --prompts DIR --out RUNDIR [--split tune|held|all]
                                 [--repeat N] [--model gemma4-e4b] [--tasks id,id]

DIR holds the five section files of defaults/ai/prompts/system. Every rollout goes
through scripts/ai/headless.sh with a throwaway HOME, so nothing of the user's is read
or written. The local model is one engine: run one of these at a time.

RUNDIR/<task>/<n>/ keeps job.json, out.json, out.config.json, out.log, trajectory.md
and checks.json; RUNDIR/summary.json has the pass counts and the prompt's size.
"""
import argparse
import datetime
import getpass
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
HEADLESS = REPO / "dots/.config/quickshell/koompi/scripts/ai/headless.sh"
TASKS = HERE / "tasks.json"
EMOJI = re.compile("[\U0001F300-\U0001FAFF\U00002600-\U000027BF\U0001F000-\U0001F2FF]")
THINK = re.compile(r"<think>.*?</think>", re.S)


def facts():
    return {
        "{AINAME}": f"{getpass.getuser()} AI",
        "{KERNEL}": os.uname().release,
        "{HOSTNAME}": os.uname().nodename,
        "{YEAR}": str(datetime.date.today().year),
    }


def fill(pattern, escape=True):
    for key, value in facts().items():
        pattern = pattern.replace(key, re.escape(value) if escape else value)
    return pattern


def load_tasks(split="all", only=None):
    tasks = json.loads(TASKS.read_text())["tasks"]
    if only:
        tasks = [t for t in tasks if t["id"] in only]
    elif split != "all":
        tasks = [t for t in tasks if t["split"] == split]
    return tasks


# ---- reading a thread ----

def parse_args(args):
    if isinstance(args, str):
        try:
            return json.loads(args) or {}
        except ValueError:
            return {"_raw": args}
    return args or {}


def calls(out):
    """Every tool call the model made, as (name, args), compacted-away ones included."""
    found = []
    # compaction rewrites the thread, but each request body still carries what came before it
    for req in out.get("requests", []):
        for m in (req.get("body") or {}).get("messages") or []:
            for c in m.get("tool_calls") or []:
                fn = c.get("function", {})
                found.append((fn.get("name", ""), parse_args(fn.get("arguments"))))
        for item in (req.get("body") or {}).get("input") or []:
            if isinstance(item, dict) and item.get("type") == "function_call":
                found.append((item.get("name", ""), parse_args(item.get("arguments"))))
    for m in out.get("messages", []):
        if m.get("role") != "assistant":
            continue
        for c in m.get("toolCalls") or []:
            fn = c.get("function", c)
            found.append((fn.get("name", ""), parse_args(fn.get("arguments", fn.get("args")))))
        fc = m.get("functionCall")
        if fc and not m.get("toolCalls"):
            found.append((fc.get("name", ""), parse_args(fc.get("args"))))
    unique = []
    for call in found:
        if call not in unique:
            unique.append(call)
    return unique


def final_text(out):
    for m in reversed(out.get("messages", [])):
        if m.get("role") == "assistant" and not m.get("functionCall") and not m.get("toolCalls"):
            text = THINK.sub("", m.get("content") or "").strip()
            if text:
                return text
    return ""


def config_value(config, path):
    node = config
    for part in path.split("."):
        if not isinstance(node, dict) or part not in node:
            return None
        node = node[part]
    return node


def same(got, want):
    return got == want or str(got).strip().lower() == str(want).strip().lower()


def check(spec, out, config):
    """(passed, why) for one check."""
    made = calls(out)
    names = [n for n, _ in made]
    text = final_text(out)
    if "called" in spec:
        name, want = spec["called"], spec.get("args", {})
        for n, args in made:
            if n == name and all(re.search(fill(rx), str(args.get(k, ""))) for k, rx in want.items()):
                return True, ""
        return False, f"no {name} call matching {want}; calls: {made}"
    if "called_any" in spec:
        hit = [n for n in names if n in spec["called_any"]]
        return bool(hit), "" if hit else f"none of {spec['called_any']} called; calls: {names}"
    if "not_called" in spec:
        bad = names if spec["not_called"] == "*" else [n for n in names if n == spec["not_called"]]
        return not bad, "" if not bad else f"called {bad}"
    if "final" in spec:
        ok = re.search(fill(spec["final"]), text, re.I) is not None
        return ok, "" if ok else f"final answer lacks /{fill(spec['final'], False)}/"
    if "final_not" in spec:
        m = re.search(fill(spec["final_not"]), text, re.I)
        return m is None, "" if m is None else f"final answer says {m.group(0)!r}"
    if "final_max" in spec:
        ok = 0 < len(text) <= spec["final_max"]
        return ok, "" if ok else f"final answer is {len(text)} characters (1-{spec['final_max']} wanted)"
    if "no_emoji" in spec:
        m = EMOJI.search(text)
        return m is None, "" if m is None else f"emoji {m.group(0)!r} in the answer"
    if "config" in spec:
        wrong = {k: config_value(config, k) for k, v in spec["config"].items() if not same(config_value(config, k), v)}
        return not wrong, "" if not wrong else f"config left {wrong}"
    raise ValueError(f"unknown check {spec}")


def render(m):
    """One message, OpenAI wire shape or the engine's own, as trajectory lines."""
    role, lines = m.get("role"), []
    text = m.get("content")
    if isinstance(text, list):
        text = " ".join(p.get("text", "") for p in text if isinstance(p, dict))
    text = THINK.sub("", text or "").strip()
    if role == "user":
        lines.append(f"[USER] {text}")
    elif role == "assistant":
        if text:
            lines.append(f"[ASSISTANT] {text}")
        for c in m.get("tool_calls") or m.get("toolCalls") or []:
            fn = c.get("function", c)
            lines.append(f"[ACTION] {fn.get('name')} {json.dumps(parse_args(fn.get('arguments', fn.get('args'))), ensure_ascii=False)}")
    elif role == "tool":
        body = text or (m.get("functionResponse") or "").strip()
        if len(body) > 600:
            body = body[:600] + f"... [{len(body) - 600} more characters]"
        lines.append(f"[OBSERVATION] {body}")
    return lines


def trajectory(task, out, results):
    """The thread as the improver reads it: what was asked, done, seen and said."""
    lines = [f"# {task['id']}", f"Goal: {task['goal']}", ""]
    seen = []
    for i, req in enumerate(out.get("requests") or []):
        body = req.get("body") or {}
        sent = [m for m in body.get("messages") or [] if m.get("role") != "system"]
        if sent[:len(seen)] != seen:
            lines.append("[COMPACTED] the engine rewrote the thread to fit the context; the model now sees:")
            seen = []
        for m in sent[len(seen):]:
            lines += render(m)
        seen = sent
        tools = [t.get("function", t).get("name") for t in body.get("tools") or []]
        lines.append(f"[REQUEST {i + 1}] tools offered: {', '.join(tools) or 'none'}")
    last = [m for m in out.get("messages", []) if m.get("role") == "assistant"]
    if last:
        lines += render(last[-1])
    if out.get("error"):
        lines.append(f"[ENGINE ERROR] {out['error']}")
    lines.append("")
    lines.append(f"[OUTCOME] {'met the goal' if all(ok for ok, _ in results) else 'did not meet the goal'}")
    return "\n".join(lines) + "\n"


# ---- running ----

def model_spec(name):
    path = Path(name)
    return json.loads(path.read_text()) if path.suffix == ".json" and path.exists() else name


def rollout(task, prompts, model, rdir, timeout):
    rdir.mkdir(parents=True, exist_ok=True)
    job = {
        "model": model,
        "turns": task["turns"],
        "approvals": task.get("approvals", {}),
        "stubs": task.get("stubs", {}),
        "promptDir": str(Path(prompts).resolve()),
        "timeoutSec": timeout,
    }
    (rdir / "job.json").write_text(json.dumps(job, indent=2))
    started = time.monotonic()
    p = subprocess.run(["bash", str(HEADLESS), str(rdir / "job.json"), str(rdir / "out.json")],
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    wall = time.monotonic() - started
    try:
        out = json.loads((rdir / "out.json").read_text())
    except (OSError, ValueError):
        out = {"ok": False, "error": f"headless exited {p.returncode}: {p.stdout[-400:]}", "messages": []}
    try:
        config = json.loads((rdir / "out.config.json").read_text())
    except (OSError, ValueError):
        config = {}
    results = [check(c, out, config) for c in task["checks"]]
    if not out.get("ok"):
        results.append((False, f"engine: {out.get('error')}"))
    (rdir / "trajectory.md").write_text(trajectory(task, out, results))
    record = {
        "task": task["id"], "passed": all(ok for ok, _ in results), "wall": round(wall, 1),
        "checks": [{"spec": c, "ok": ok, "why": why} for c, (ok, why) in zip(task["checks"] + [{"engine": True}], results)],
        "systemPromptBytes": len((out.get("systemPrompt") or "").encode()),
        "toolBytes": len(json.dumps(((out.get("requests") or [{}])[0].get("body") or {}).get("tools") or [])),
    }
    (rdir / "checks.json").write_text(json.dumps(record, indent=2))
    return record


def run(prompts, out_dir, tasks, model, repeat=1, timeout=180, log=print):
    out_dir = Path(out_dir)
    records = []
    for task in tasks:
        for n in range(repeat):
            r = rollout(task, prompts, model, out_dir / task["id"] / str(n), timeout)
            records.append(r)
            why = "; ".join(c["why"] for c in r["checks"] if not c["ok"])
            log(f"{'pass' if r['passed'] else 'FAIL'}  {task['id']}#{n}  {r['wall']}s  {why}")
    summary = {
        "prompts": str(prompts), "model": model if isinstance(model, str) else model.get("model"),
        "repeat": repeat, "passed": sum(r["passed"] for r in records), "total": len(records),
        "tasks": {t["id"]: sum(r["passed"] for r in records if r["task"] == t["id"]) for t in tasks},
        "systemPromptBytes": max((r["systemPromptBytes"] for r in records), default=0),
        "toolBytes": max((r["toolBytes"] for r in records), default=0),
    }
    (out_dir / "summary.json").write_text(json.dumps(summary, indent=2))
    return summary


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--prompts", default=str(REPO / "dots/.config/quickshell/koompi/defaults/ai/prompts/system"))
    ap.add_argument("--out", required=True)
    ap.add_argument("--split", choices=["tune", "held", "all"], default="all")
    ap.add_argument("--tasks", default="", help="comma-separated task ids, instead of --split")
    ap.add_argument("--repeat", type=int, default=1)
    ap.add_argument("--model", default="gemma4-e4b", help="a discovered model id, or a .json ai.extraModels entry")
    ap.add_argument("--timeout", type=int, default=180)
    args = ap.parse_args()
    tasks = load_tasks(args.split, [t for t in args.tasks.split(",") if t])
    if not tasks:
        sys.exit("no tasks selected")
    s = run(args.prompts, args.out, tasks, model_spec(args.model), args.repeat, args.timeout)
    print(f"{s['passed']}/{s['total']} passed; system prompt {s['systemPromptBytes']} B, tools {s['toolBytes']} B")


if __name__ == "__main__":
    main()
