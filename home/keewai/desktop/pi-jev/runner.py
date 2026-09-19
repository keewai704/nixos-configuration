import fcntl
import json
import os
import re
import signal
import sys
import time
from pathlib import Path
from urllib.parse import urlsplit

from jev_ultrafast import agent as agent_module
from jev_ultrafast.browser import Browser, StalePage
from jev_ultrafast.model import field_context, field_text


class StopRun(BaseException):
    def __init__(self, reason):
        self.reason = reason


def text(value, limit):
    cleaned = "".join(c for c in str(value) if c.isprintable() or c in "\n\t")
    return cleaned.encode("utf-8")[:limit].decode("utf-8", errors="ignore")


def origin(url):
    parsed = urlsplit(url)
    if (
        parsed.scheme not in {"http", "https"}
        or not parsed.hostname
        or parsed.username is not None
        or parsed.password is not None
        or len(url) > 2048
    ):
        raise ValueError("invalid_url")
    return (
        parsed.scheme,
        parsed.hostname.lower(),
        parsed.port
        if parsed.port is not None
        else (443 if parsed.scheme == "https" else 80),
    )


class ScopedBrowser(Browser):
    owned = None

    def __init__(self, url):
        self.allowed_origin = origin(url)
        self.outside_url = None
        ScopedBrowser.owned = self
        super().__init__(url)

    def close(self):
        if getattr(self, "target", None):
            super().close()

    def observe(self, screenshot=False):
        page = super().observe(screenshot=screenshot)
        if origin(page["url"]) != self.allowed_origin:
            self.outside_url = text(page["url"], 2048)
            raise StopRun("origin_changed")
        return page


def emit(event):
    print(json.dumps(event, ensure_ascii=True), flush=True)


def receive():
    line = sys.stdin.buffer.readline(32769)
    if not line:
        raise StopRun("cancelled")
    if len(line) > 32768 or not line.endswith(b"\n"):
        raise ValueError("invalid_request")
    result = json.loads(line)
    if not isinstance(result, dict):
        raise TypeError("invalid_request")
    return result


def configuration(request):
    if (
        not isinstance(request.get("goal"), str)
        or not 1 <= len(request["goal"].strip()) <= 2000
    ):
        raise ValueError("invalid_goal")
    if not isinstance(request.get("url"), str):
        raise TypeError("invalid_url")
    origin(request["url"])
    for key, default, maximum in (("maxSteps", 12, 30), ("timeoutSeconds", 120, 300)):
        value = request.setdefault(key, default)
        if type(value) is not int or not 1 <= value <= maximum:
            raise ValueError("invalid_limit")
    expected = request.setdefault("expect", {})
    if not isinstance(expected, dict) or set(expected) - {
        "urlContains",
        "textContains",
    }:
        raise ValueError("invalid_expectation")
    if "urlContains" in expected and (
        not isinstance(expected["urlContains"], str)
        or not 1 <= len(expected["urlContains"]) <= 500
    ):
        raise ValueError("invalid_expectation")
    fragments = expected.get("textContains", [])
    if (
        not isinstance(fragments, list)
        or len(fragments) > 10
        or any(
            not isinstance(fragment, str) or not 1 <= len(fragment) <= 500
            for fragment in fragments
        )
    ):
        raise ValueError("invalid_expectation")
    return request


def load_credentials():
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    env_file = config_home / "jev-ultrafast" / ".env"
    allowed = {
        "TYPESAFE_API_KEY",
        "TYPESAFE_MODEL",
        "TEXT_MODEL_API_KEY",
        "TEXT_MODEL_BASE_URL",
        "TEXT_MODEL",
        "TEXT_MODEL_REASONING",
    }
    values = {}
    if env_file.exists():
        for line in env_file.read_text().splitlines():
            if "=" in line and not line.startswith("#"):
                key, value = line.split("=", 1)
                if key in allowed:
                    values[key] = value
    key_file = Path(
        os.environ.get("TYPESAFE_API_KEY_FILE", config_home / "typesafe" / "api-key")
    )
    if not os.environ.get("TYPESAFE_API_KEY") and key_file.exists():
        os.environ["TYPESAFE_API_KEY"] = key_file.read_text().strip()
    for key, value in values.items():
        if not os.environ.get(key):
            os.environ[key] = value
    if not os.environ.get("TYPESAFE_API_KEY"):
        raise StopRun("missing_typesafe_key")


def verification(page, expected):
    checks = []
    if "urlContains" in expected:
        checks.append(
            {
                "field": "url",
                "contains": expected["urlContains"],
                "passed": expected["urlContains"] in page["url"] if page else None,
            }
        )
    for fragment in expected.get("textContains", []):
        checks.append(
            {
                "field": "visible_text",
                "contains": fragment,
                "passed": fragment in page["text"] if page else None,
            }
        )
    status = (
        "not_requested"
        if not checks
        else "unknown"
        if not page
        else "passed"
        if all(c["passed"] for c in checks)
        else "failed"
    )
    return {"status": status, "checks": checks}


def evidence(page):
    if page is None:
        return None
    controls = []
    nodes = set()
    for action in page["actions"]:
        if action.get("node") is None or action["node"] in nodes:
            continue
        nodes.add(action["node"])
        controls.append(
            {
                key: text(action[key], 200)
                for key in (
                    "role",
                    "label",
                    "value",
                    "current_value",
                    "checked",
                    "selected",
                    "expanded",
                )
                if key in action
            }
        )
    selected = controls[:20]
    while len(json.dumps(selected, ensure_ascii=False).encode("utf-8")) > 4096:
        selected.pop()
    return {
        "url": text(page["url"], 2048),
        "title": text(page["title"], 300),
        "visible_text": text(page["text"], 6000),
        "controls": selected,
        "controls_truncated": len(controls) > len(selected)
        or bool(page.get("omitted_actions")),
        "scope": "Current viewport only; not a full-page or accessibility audit.",
    }


def stop_signal(signum, _frame):
    raise StopRun("timeout" if signum == signal.SIGALRM else "cancelled")


def run(request):
    started = time.monotonic()
    agent = None
    page = None
    reason = "error"
    phase = "setup"
    attempted = 0
    cleanup = "not_opened"
    error_type = None
    ScopedBrowser.owned = None
    signal.signal(signal.SIGTERM, stop_signal)
    signal.signal(signal.SIGINT, stop_signal)
    signal.signal(signal.SIGALRM, stop_signal)
    signal.setitimer(signal.ITIMER_REAL, request["timeoutSeconds"])
    try:
        load_credentials()
        agent_module.Browser = ScopedBrowser
        agent = agent_module.Agent(request["url"], request["goal"], screenshots=False)
        cleanup = "pending"
        for decision_id in range(1, request["maxSteps"] + 1):
            phase = "prediction"
            agent.command("predict")
            state = agent.state
            decision = state["decision"]
            if decision["choice"] in {"DONE", "BLOCKED"}:
                agent.command("act", {"fingerprint": state["page"]["fingerprint"]})
                reason = "agent_" + state["status"]
                break
            action = next(
                a for a in state["page"]["actions"] if a["id"] == decision["choice"]
            )
            value = None
            if action["kind"] == "fill":
                phase = "text_generation"
                if not os.environ.get("TEXT_MODEL_API_KEY"):
                    raise StopRun("missing_text_model_key")
                context = field_context(
                    state["goal"], action, state["page"], state["history"]
                )
                value, helper = field_text(context)
                if any(not c.isprintable() and c not in "\n\t" for c in value):
                    raise StopRun("invalid_field_value")
                agent.pending_text = (context, value, helper)
                state["text_calls"].append(
                    {**helper, "field": action["label"], "value": value}
                )
            emit(
                {
                    "event": "proposal",
                    "id": decision_id,
                    "operation": decision["operation"],
                    "target": text(action["label"], 300),
                    "value": value,
                    "url": text(state["page"]["url"], 2048),
                }
            )
            phase = "approval"
            approval = receive()
            if (
                set(approval) != {"id", "approve"}
                or type(approval["id"]) is not int
                or approval["id"] != decision_id
                or approval["approve"] is not True
            ):
                raise StopRun("cancelled")
            phase = "execution"
            attempted += 1
            agent.command("act", {"fingerprint": state["page"]["fingerprint"]})
            emit(
                {
                    "event": "progress",
                    "actions": len(state["history"]),
                    "operation": decision["operation"],
                }
            )
            if state["status"] == "blocked":
                reason = "agent_blocked"
                break
        else:
            reason = "step_limit"
        phase = "verification"
        page = agent.browser.observe(screenshot=False)
    except StopRun as error:
        reason = error.reason
    except StalePage:
        reason = "stale_page"
    except Exception as error:
        reason = "execution_uncertain" if phase == "execution" else "error"
        if phase in {"prediction", "text_generation"}:
            status = re.fullmatch(
                r"Model provider returned HTTP (\d{3}); no action executed\.",
                str(error),
            )
            if status:
                reason = "provider_http_" + status[1]
        error_type = type(error).__name__
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        browser = agent.browser if agent else ScopedBrowser.owned
        if browser is not None:
            try:
                browser.close()
                cleanup = "closed_owned_tab"
            except (Exception, StopRun):
                cleanup = "failed_to_close_owned_tab"
    state = agent.state if agent else {}
    history = [
        {
            "step": h["step"],
            "operation": h["operation"],
            "target": text(h["action"], 120),
        }
        for h in state.get("history", [])
    ]
    return {
        "event": "result",
        "stop_reason": reason,
        "agent_status": state.get("status", "not_started"),
        "verification": verification(page, request["expect"]),
        "evidence": evidence(page),
        "last_observed_url": text(state.get("page", {}).get("url", ""), 2048),
        "outside_url": getattr(browser, "outside_url", None),
        "actions": history,
        "attempted_actions": attempted,
        "decision_calls": len(state.get("decisions", [])),
        "text_calls": len(state.get("text_calls", [])),
        "elapsed_ms": round((time.monotonic() - started) * 1000),
        "cleanup": cleanup,
        "error_type": error_type,
        "limits": "DONE is not proof of success. Only supplied predicates are checked. Origin checks are not a network sandbox. Never automatically retry uncertain execution.",
    }


def main():
    try:
        request = configuration(receive())
        runtime = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
        fd = os.open(
            runtime / "pi-jev.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600
        )
        with os.fdopen(fd, "w") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise StopRun("another_jev_run_is_active") from None
            emit(run(request))
    except StopRun as error:
        emit({"event": "result", "stop_reason": error.reason, "evidence": None})
    except Exception as error:
        emit(
            {
                "event": "result",
                "stop_reason": "setup_error",
                "error_type": type(error).__name__,
                "evidence": None,
            }
        )


if __name__ == "__main__":
    main()
