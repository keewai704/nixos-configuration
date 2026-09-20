import json
import os
import sys
import time
import uuid
from pathlib import Path

import pyatspi
from gi.repository import GLib


class Refused(Exception):
    pass


def process_identity(pid):
    path = Path(f"/proc/{pid}")
    if path.stat().st_uid != os.getuid():
        raise Refused("target_not_owned")
    return (path / "stat").read_text().rsplit(")", 1)[1].split()[19]


def application(pid):
    matches = []
    for app in pyatspi.Registry.getDesktop(0):
        try:
            app_pid = app.get_process_id()
        except (GLib.Error, RuntimeError):
            app_pid = None
        if app_pid == pid:
            matches.append(app)
    if len(matches) != 1:
        raise Refused("application_missing_or_ambiguous")
    app = matches[0]
    if app.get_toolkit_name().lower() not in ("gtk", "qt"):
        raise Refused("unsupported_toolkit")
    return app


def window(pid, title):
    matches = [child for child in application(pid) if child.name == title]
    if len(matches) != 1:
        raise Refused("window_missing_or_ambiguous")
    return matches[0]


def row_for(obj, index, parent):
    role = obj.getRoleName()
    if role in ("password text", "terminal", "document web", "embedded"):
        raise Refused("sensitive_or_web_surface")
    states = obj.getState()
    if states.contains(pyatspi.STATE_DEFUNCT):
        raise Refused("defunct_element")
    interfaces = pyatspi.listInterfaces(obj)
    value = None
    if "Text" in interfaces:
        text = obj.queryText()
        if text.characterCount > 1000:
            raise Refused("text_limit")
        value = text.getText(0, -1)
    actions = []
    if "Action" in interfaces:
        action = obj.queryAction()
        count = action.nActions
        if not 0 <= count <= 8:
            raise Refused("action_count_limit")
        for action_index in range(count):
            name = action.getName(action_index)
            if len(name) > 100:
                raise Refused("action_name_limit")
            actions.append(name)
    label = obj.name or ""
    if len(label) > 200:
        raise Refused("label_limit")
    return {
        "element_index": index,
        "parent_index": parent,
        "role": role,
        "label": label,
        "value": value,
        "enabled": states.contains(pyatspi.STATE_ENABLED)
        and states.contains(pyatspi.STATE_SENSITIVE)
        and states.contains(pyatspi.STATE_SHOWING),
        "selected": states.contains(pyatspi.STATE_SELECTED)
        if states.contains(pyatspi.STATE_SELECTABLE)
        else states.contains(pyatspi.STATE_CHECKED)
        if role in ("check box", "radio button", "toggle button")
        else None,
        "actions": actions,
        "editable": "EditableText" in interfaces
        and states.contains(pyatspi.STATE_EDITABLE),
    }


class Desktop:
    def __init__(self):
        self.identity = None
        self.scope = None
        self.root = None
        self.objects = {}

    def bind(self, args):
        pid = args["pid"]
        if type(pid) is not int or not 0 < pid < 2147483648:
            raise Refused("invalid_pid")
        identity = process_identity(pid)
        if self.identity is None:
            self.identity = (pid, identity)
        if self.identity != (pid, identity):
            raise Refused("process_changed")
        return pid

    def observe(self, args):
        self.objects = {}
        pid = self.bind(args)
        title = args["window_title"]
        if not isinstance(title, str) or not title or len(title) > 300:
            raise Refused("invalid_window_title")
        scope = (pid, title)
        if self.scope is not None and scope != self.scope:
            raise Refused("window_scope_changed")
        self.scope = scope
        root = window(pid, title)
        if self.root is not None and root != self.root:
            raise Refused("window_changed")
        self.root = root
        root.clearCache()
        rows = []
        objects = {}
        snapshot = uuid.uuid4().hex

        def visit(obj, parent, depth):
            if len(rows) >= 80 or depth > 20:
                raise Refused("tree_limit")
            obj.clearCache()
            index = len(rows)
            row = row_for(obj, index, parent)
            token = f"{snapshot}:{index}"
            rows.append(row | {"element_token": token})
            objects[token] = (obj, row)
            for child in obj:
                visit(child, index, depth + 1)

        visit(root, None, 0)
        if len(json.dumps(rows, ensure_ascii=False).encode()) > 24000:
            raise Refused("state_limit")
        self.bind(args)
        if window(pid, title) != root:
            raise Refused("window_changed")
        self.objects = objects
        return {"elements": rows}

    def act(self, method, args):
        pid = self.bind(args)
        if self.scope != (pid, args["window_title"]):
            raise Refused("window_scope_changed")
        if window(pid, args["window_title"]) != self.root:
            raise Refused("window_changed")
        obj, expected = self.objects.get(args["element_token"], (None, None))
        self.objects = {}
        if obj is None:
            raise Refused("stale_element")
        obj.clearCache()
        if (
            row_for(obj, expected["element_index"], expected["parent_index"])
            != expected
        ):
            raise Refused("element_changed")
        if not expected["enabled"]:
            raise Refused("element_disabled")
        if method == "click":
            if not expected["actions"]:
                raise Refused("no_accessibility_action")
            accepted = obj.queryAction().doAction(0)
            effect = "unverifiable"
        else:
            value = args["value"]
            if (
                not isinstance(value, str)
                or len(value) > 1000
                or not expected["editable"]
            ):
                raise Refused("not_editable_or_invalid_value")
            accepted = obj.queryEditableText().setTextContents(value)
            obj.clearCache()
            effect = (
                "confirmed"
                if obj.queryText().getText(0, -1) == value
                else "unverifiable"
            )
        return {"route": "accessibility", "effect": effect if accepted else "partial"}

    def verify(self, args):
        predicates = args["expect"]
        if not isinstance(predicates, list) or not 1 <= len(predicates) <= 8:
            raise Refused("invalid_predicates")
        consecutive = 0
        started = time.monotonic()
        samples = 0
        while True:
            rows = self.observe(args)["elements"]
            checks = []
            for index, predicate in enumerate(predicates):
                matches = [
                    row
                    for row in rows
                    if row["role"] == predicate["role"]
                    and row["label"] == predicate["label"]
                ]
                status = "unknown"
                if len(matches) == 1:
                    row = matches[0]
                    status = (
                        "satisfied"
                        if all(
                            row[key] == predicate[key]
                            for key in ("value", "selected")
                            if key in predicate
                        )
                        else "unsatisfied"
                    )
                checks.append({"index": index, "status": status})
            samples += 1
            status = (
                "satisfied"
                if all(check["status"] == "satisfied" for check in checks)
                else "unknown"
                if any(check["status"] == "unknown" for check in checks)
                else "unsatisfied"
            )
            consecutive = consecutive + 1 if status == "satisfied" else 0
            if consecutive >= 2 or time.monotonic() - started >= 1.5:
                return {
                    "status": status
                    if status != "satisfied" or consecutive >= 2
                    else "unknown",
                    "stable": consecutive >= 2,
                    "predicates": checks,
                    "samples": samples,
                    "elements": rows,
                }
            time.sleep(0.1)

    def call(self, method, args):
        if method == "list_windows":
            pid = self.bind(args)
            windows = [
                {"window_title": child.name, "role": child.getRoleName()}
                for child in application(pid)
            ]
            if len(windows) > 20 or len(json.dumps(windows).encode()) > 8000:
                raise Refused("window_list_limit")
            return {"pid": pid, "windows": windows}
        if method == "get_window_state":
            return self.observe(args)
        if method in ("click", "set_value"):
            return self.act(method, args)
        if method == "verify_state":
            return self.verify(args)
        raise Refused("unsupported_operation")


def main():
    desktop = Desktop()
    while line := sys.stdin.buffer.readline(65537):
        if len(line) > 65536 or not line.endswith(b"\n"):
            return 1
        request = json.loads(line)
        try:
            result = desktop.call(request["method"], request["params"])
        except Refused as error:
            result = {"refusal": str(error)}
        except (GLib.Error, OSError, RuntimeError, KeyError, TypeError, ValueError):
            result = {"refusal": "accessibility_error"}
        print(json.dumps({"id": request["id"], "result": result}), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
