"""Pure CPS semantic graph validation and ordered link-plan expansion."""

def _edge_target(edge):
    return edge.target

def find_cycle(graph, allowed_kinds):
    """Returns a clear DFS cycle as edges, or None.

    `graph` maps node names to ordered edge structs with `target` and `kind`.
    Input edge order is preserved, giving deterministic diagnostics.
    """
    visited = {}
    step_budget = 1
    for edges in graph.values():
        step_budget += len(edges) + 1

    for root in sorted(graph.keys()):
        if root in visited:
            continue
        active = {root: 0}
        frames = [{"node": root, "index": 0}]
        path_edges = []
        for _ in range(step_budget):
            if not frames:
                continue
            frame = frames[-1]
            edges = [edge for edge in graph.get(frame["node"], []) if edge.kind in allowed_kinds]
            if frame["index"] >= len(edges):
                completed = frames.pop()["node"]
                active.pop(completed)
                visited[completed] = True
                if frames:
                    path_edges.pop()
                continue
            edge = edges[frame["index"]]
            frame["index"] += 1
            target = _edge_target(edge)
            if target in active:
                return path_edges[active[target]:] + [edge]
            if target not in visited:
                active[target] = len(frames)
                frames.append({"node": target, "index": 0})
                path_edges.append(edge)
        if frames:
            fail("CPS graph cycle analysis exceeded deterministic step budget")
    return None

def expand_link_plan(root, graph):
    """Expands canonical CPS link order depth-first, preserving duplicates.

    Each node contributes itself, followed by `requires` edges in source order,
    then `link_requires` edges in source order. No global visited set is used,
    because repeated occurrences are intentional CPS semantics. Callers must
    reject link cycles first with `find_cycle`.
    """
    output = []
    pending = [root]
    # Acyclic graphs can still expand exponentially when duplicates are
    # intentional. Bound generated actions/providers against hostile inputs.
    for _ in range(100000):
        if not pending:
            return output
        node = pending.pop()
        output.append(node)
        children = []
        node_edges = graph.get(node, [])
        for kind in ["requires", "link_requires"]:
            children.extend([edge.target for edge in node_edges if edge.kind == kind])
        pending.extend(reversed(children))
    fail("canonical CPS link plan exceeds the 100000-occurrence safety limit")
