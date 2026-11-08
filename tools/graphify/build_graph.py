#!/usr/bin/env python3
"""Rebuild this repo's code graph with graphify.

    pip install "graphifyy[sql]"
    python tools/graphify/build_graph.py

Writes, at the repo root:
    graphify-out/graph.html        interactive graph (dark theme), committed
    graphify-out/GRAPH_REPORT.md   hubs, communities, stats, committed
    graphify-out/graph.json        full symbol graph, git-ignored (too large for git)

How it is built, and why:
- Only files tracked at HEAD are read (`git archive`), in a temp copy, so untracked
  folders never enter the graph and graphify never writes into the working tree.
- Only code nodes are kept. graphify also turns markdown headings into nodes; docs are
  left out because they are where patient details could slip in.
- No AI is used. GRAPHIFY_BACKEND=none disables every LLM backend, and communities are
  named after their most-connected symbol. Nothing leaves this machine.

The same script lives in CLINICAL, WEBSITE, STUDIO and iOS. The cross-repo page is
built afterwards by CLINICAL's tools/graphify/build_ecosystem.py.
"""
from __future__ import annotations

import io
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

GRAPHIFY = os.environ.get("GRAPHIFY_BIN", "graphify")

# Small screens: stack graphify's sidebar under the graph instead of beside it.
MOBILE_CSS = (
    "  @media (max-width: 720px) { body { flex-direction: column; } "
    "#sidebar { width: 100%; height: 46%; border-left: 0; border-top: 1px solid var(--border); } }\n"
)


def run(cmd: list[str], cwd: Path, env: dict) -> None:
    print("$", " ".join(cmd), flush=True)
    proc = subprocess.run(cmd, cwd=cwd, env=env, text=True, capture_output=True)
    for line in (proc.stdout + proc.stderr).splitlines():
        if "AST extraction:" not in line and not line.startswith("Tip"):
            print("  " + line[:300])
    if proc.returncode != 0:
        sys.exit(f"graphify failed with exit code {proc.returncode}")


def keep_code_only(graph_path: Path) -> tuple[int, int]:
    g = json.loads(graph_path.read_text())
    keep = {n["id"] for n in g["nodes"] if n.get("file_type") == "code"}
    g["nodes"] = [n for n in g["nodes"] if n["id"] in keep]
    g["links"] = [l for l in g["links"] if l["source"] in keep and l["target"] in keep]
    g["hyperedges"] = []
    graph_path.write_text(json.dumps(g))
    return len(g["nodes"]), len(g["links"])


def main() -> None:
    root = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
    repo = root.name
    if shutil.which(GRAPHIFY) is None:
        sys.exit('graphify is not installed: pip install "graphifyy[sql]"')

    env = {k: v for k, v in os.environ.items()}
    env["GRAPHIFY_BACKEND"] = "none"

    with tempfile.TemporaryDirectory(prefix="graphify-") as tmp:
        work = Path(tmp) / repo
        work.mkdir()
        archive = subprocess.check_output(["git", "archive", "HEAD"], cwd=root)
        with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
            tar.extractall(work, filter="data")

        run([GRAPHIFY, "update", "."], work, env)
        out = work / "graphify-out"
        nodes, edges = keep_code_only(out / "graph.json")
        print(f"code only: {nodes:,} nodes, {edges:,} edges")
        for stale in out.glob("*label*"):
            stale.unlink()
        run([GRAPHIFY, "cluster-only", "."], work, env)

        html = (out / "graph.html").read_text()
        html = html.replace("</style>", MOBILE_CSS + "</style>", 1)
        html = html.replace("<title>graphify - graphify-out/graph.html</title>", f"<title>{repo} code graph</title>")

        dest = root / "graphify-out"
        dest.mkdir(exist_ok=True)
        (dest / "graph.html").write_text(html)
        shutil.copy(out / "GRAPH_REPORT.md", dest / "GRAPH_REPORT.md")
        shutil.copy(out / "graph.json", dest / "graph.json")

    print(f"\nwrote {dest}/graph.html, GRAPH_REPORT.md and graph.json (graph.json is git-ignored)")


if __name__ == "__main__":
    main()
