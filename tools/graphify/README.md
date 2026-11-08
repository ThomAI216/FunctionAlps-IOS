# Code graph (graphify)

`graphify-out/graph.html` is this repo's interactive code graph; `graphify-out/GRAPH_REPORT.md`
lists its most-connected symbols and communities. Code only: no docs, no AI, nothing leaves
the machine. `graphify-out/graph.json` (the full symbol graph) is git-ignored.

Rebuild:

```bash
pip install "graphifyy[sql]"
python tools/graphify/build_graph.py
```

The cross-repo page and the "agent at work" animation live in FunctionAlps-CLINICAL
(`graphify-out/ecosystem/`, see its `tools/graphify/README.md`).
