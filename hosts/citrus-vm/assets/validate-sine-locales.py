import json
import re
import sys
from collections import Counter
from pathlib import Path

from fluent.syntax import FluentParser

parser = FluentParser(with_spans=False)
reference_types = {
    "FunctionReference",
    "MessageReference",
    "TermReference",
    "VariableReference",
}

def identifier(node):
    value = node.get("id", {})
    name = value.get("name", "")
    attribute = node.get("attribute")
    if attribute:
        name += "." + attribute.get("name", "")
    return name

def collect_structure(node, result):
    if isinstance(node, list):
        for item in node:
            collect_structure(item, result)
        return

    if not isinstance(node, dict):
        return

    node_type = node.get("type")
    if node_type in reference_types:
        result[(node_type, identifier(node))] += 1
    elif node_type == "Variant":
        key = node.get("key", {})
        result[("Variant", key.get("type", ""), str(key.get("name", key.get("value", ""))))] += 1
    elif node_type == "TextElement":
        value = node.get("value", "")
        for closing, tag in re.findall(r"<\s*(/?)\s*([A-Za-z][\w:-]*)\b", value):
            result[("Markup", closing, tag)] += 1
        for slot in re.findall(r'data-l10n-name\s*=\s*"([^"]+)"', value):
            result[("Slot", slot)] += 1
        return

    for value in node.values():
        collect_structure(value, result)

def load_schema(path):
    resource = parser.parse(path.read_text(encoding="utf-8"))
    junk = [entry for entry in resource.body if entry.__class__.__name__ == "Junk"]
    if junk:
        raise SystemExit(f"invalid Fluent syntax in {path}: {len(junk)} junk entries")

    schema = {}
    for entry in resource.body:
        if entry.__class__.__name__ not in {"Message", "Term"}:
            continue
        data = entry.to_json()
        entry_id = data["id"]["name"]
        if entry.__class__.__name__ == "Term":
            entry_id = "-" + entry_id
        attributes = tuple(sorted(attribute["id"]["name"] for attribute in data.get("attributes", [])))
        structure = Counter()
        collect_structure(data, structure)
        schema[entry_id] = {
            "attributes": attributes,
            "structure": sorted((list(key), count) for key, count in structure.items()),
        }
    return schema

source_root = Path(sys.argv[1])
target_root = Path(sys.argv[2])
for filename in ("sine-preferences.ftl", "sine-toasts.ftl", "sine-cmdpalette.ftl"):
    source_schema = load_schema(source_root / filename)
    target_schema = load_schema(target_root / filename)
    if source_schema != target_schema:
        print(f"Fluent schema mismatch in {filename}", file=sys.stderr)
        print(json.dumps({"en-US": source_schema, "ja": target_schema}, ensure_ascii=False, indent=2), file=sys.stderr)
        raise SystemExit(1)
