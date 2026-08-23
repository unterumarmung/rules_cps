"""Configured CPS component model and separate semantic dependency graphs."""

load(":configuration.bzl", "effective_preferences", "merge_nullable", "select_configuration")
load(":graph.bzl", "find_cycle")
load(":requirements.bzl", "parse_component_requirement")

_SUPPORTED_USE_TYPES = {
    "archive": True,
    "dylib": True,
    "executable": True,
    "interface": True,
    "module": True,
    "symbolic": True,
}

def component_key(package, component, configuration):
    """Returns a collision-free deterministic key for a configured component."""
    return json.encode([package, component, configuration])

def decode_component_key(key):
    """Returns `[package, component, configuration]` for `component_key`."""
    return json.decode(key)

def _resolve_component(requirement, source_configuration, packages, preferences):
    if requirement.package not in packages:
        fail("component requirement %r refers to unavailable CPS package %s" % (requirement.source, requirement.package))
    package = packages[requirement.package]
    if requirement.component not in package["components"]:
        fail("component requirement %r refers to missing component %s in CPS package %s" % (
            requirement.source,
            requirement.component,
            requirement.package,
        ))
    component = package["components"][requirement.component]
    if component["type"] not in _SUPPORTED_USE_TYPES:
        fail("component requirement %r uses unsupported CPS component type %s at %s.components.%s" % (
            requirement.source,
            component["type"],
            package["source"],
            requirement.component,
        ))
    available = component.get("configurations", {}).keys()
    if requirement.configuration_mode == "same":
        selected = source_configuration
        if selected != None and selected not in available:
            fail("same-configuration requirement %r requests %s from %s:%s; available configurations: %r" % (
                requirement.source,
                selected,
                requirement.package,
                requirement.component,
                sorted(available),
            ))
    elif requirement.configuration_mode == "exact":
        selected = select_configuration(available, [], exact = requirement.configuration)
    else:
        selected = select_configuration(
            available,
            effective_preferences(preferences.get(requirement.package, []), [], package.get("configurations", [])),
        )
    configured = merge_nullable(component, component.get("configurations", {})[selected]) if selected != None else component
    if component["type"] not in ["interface", "symbolic"] and configured.get("location") == None:
        fail("configured CPS component %s:%s@%s of type %s has no location after configuration selection (%s)" % (
            requirement.package,
            requirement.component,
            selected,
            component["type"],
            package["source"],
        ))
    return struct(
        key = component_key(requirement.package, requirement.component, selected),
        package = requirement.package,
        component = requirement.component,
        configuration = selected,
        data = configured,
    )

def _cycle_message(label, cycle):
    lines = ["CPS %s cycle detected:" % label]
    for edge in cycle:
        lines.append("  %s --%s--> %s" % (edge.source, edge.kind, edge.target))
    return "\n".join(lines)

def build_semantic_model(packages, roots, preferences = {}):
    """Builds configured nodes and distinct compile/link/runtime edge channels.

    `packages` is keyed by canonical CPS package identity after explicit binding.
    `roots` contains absolute component specifications. Configuration selection
    is performed per component and `@@` is resolved against the source node.
    Edge list order exactly follows each CPS field and channel. Compile and link
    cycles fail; runtime-only cycles are retained and terminate during closure.
    """
    nodes = {}
    graph = {}
    root_keys = []
    pending = []
    for root in roots:
        parsed = parse_component_requirement(root, "")
        if not parsed.package:
            fail("semantic model root must be an absolute CPS component specification: %r" % root)
        resolved = _resolve_component(parsed, None, packages, preferences)
        root_keys.append(resolved.key)
        pending.append(resolved)

    for _ in range(100000):
        if not pending:
            break
        node = pending.pop()
        if node.key in nodes:
            continue
        nodes[node.key] = node
        edges = []
        for kind in ["requires", "compile_requires", "link_requires", "dyld_requires"]:
            for specification in node.data.get(kind, []):
                requirement = parse_component_requirement(specification, node.package)
                target = _resolve_component(requirement, node.configuration, packages, preferences)
                edges.append(struct(
                    source = node.key,
                    target = target.key,
                    kind = kind,
                    requirement = requirement,
                ))
                if target.key not in nodes:
                    pending.append(target)
        graph[node.key] = edges
    if pending:
        fail("configured CPS semantic graph exceeds the 100000-node safety limit")

    compile_cycle = find_cycle(graph, ["requires", "compile_requires"])
    if compile_cycle != None:
        fail(_cycle_message("compile", compile_cycle))
    link_cycle = find_cycle(graph, ["requires", "link_requires"])
    if link_cycle != None:
        fail(_cycle_message("link", link_cycle))
    return struct(nodes = nodes, graph = graph, roots = root_keys)

def expand_plan(root, graph, kind_order):
    """Depth-first expands an ordered semantic plan, preserving duplicates."""
    output = []
    pending = [root]
    for _ in range(100000):
        if not pending:
            return output
        node = pending.pop()
        output.append(node)
        children = []
        edges = graph.get(node, [])
        for kind in kind_order:
            children.extend([edge.target for edge in edges if edge.kind == kind])
        pending.extend(reversed(children))
    fail("CPS semantic plan exceeds the 100000-occurrence safety limit")

def compile_plan(root, graph):
    """Returns requires then compile_requires depth-first compile order."""
    return expand_plan(root, graph, ["requires", "compile_requires"])

def link_plan(root, graph):
    """Returns requires then link_requires depth-first link order."""
    return expand_plan(root, graph, ["requires", "link_requires"])

def runtime_closure(root, graph):
    """Returns a deterministic unique runtime closure; runtime cycles are legal."""
    result = []
    seen = {}
    pending = [root]
    for _ in range(100000):
        if not pending:
            return result
        node = pending.pop()
        if node in seen:
            continue
        seen[node] = True
        result.append(node)
        edges = graph.get(node, [])
        children = []
        for kind in ["requires", "link_requires", "dyld_requires"]:
            children.extend([edge.target for edge in edges if edge.kind == kind])
        pending.extend(reversed(children))
    fail("CPS runtime closure exceeds the 100000-node safety limit")
