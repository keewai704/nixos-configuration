import json
import sys

from aiohttp import ClientSession, ClientTimeout, web

ANTHROPIC = "https://api.anthropic.com"
GO = "https://opencode.ai/inference/go/anthropic"
PREFIX = "opencode-go/"
HOP = {
    "connection",
    "content-length",
    "host",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailer",
    "trailers",
    "transfer-encoding",
    "upgrade",
}

host, port, key_file = sys.argv[1], int(sys.argv[2]), sys.argv[3]


def go_target(request, body):
    if request.method != "POST" or not request.path.startswith("/v1/messages"):
        return None
    try:
        payload = json.loads(body)
    except ValueError:
        return None
    model = payload.get("model") if isinstance(payload, dict) else None
    if not isinstance(model, str) or not model.startswith(PREFIX):
        return None
    payload["model"] = model[len(PREFIX):]
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode()


def go_headers(headers):
    with open(key_file) as f:
        key = f.read().strip()
    result = {
        k: v
        for k, v in headers.items()
        if k.lower() not in {"authorization", "x-api-key", "anthropic-beta"}
    }
    betas = [
        b.strip()
        for b in headers.get("anthropic-beta", "").split(",")
        if b.strip() and not b.strip().startswith("oauth-")
    ]
    if betas:
        result["anthropic-beta"] = ",".join(betas)
    session = headers.get("x-claude-code-session-id")
    if session and "x-opencode-session" not in headers:
        result["x-opencode-session"] = session
    result["Authorization"] = f"Bearer {key}"
    return result


async def handle(request):
    body = await request.read()
    headers = {k: v for k, v in request.headers.items() if k.lower() not in HOP}
    upstream = ANTHROPIC
    go_body = go_target(request, body)
    if go_body is not None:
        upstream, body, headers = GO, go_body, go_headers(headers)
    session = request.app["session"]
    async with session.request(
        request.method,
        upstream + request.path_qs,
        headers=headers,
        data=body or None,
        allow_redirects=False,
    ) as upstream_response:
        response = web.StreamResponse(
            status=upstream_response.status,
            reason=upstream_response.reason,
            headers={
                k: v
                for k, v in upstream_response.headers.items()
                if k.lower() not in HOP
            },
        )
        await response.prepare(request)
        try:
            async for chunk in upstream_response.content.iter_any():
                await response.write(chunk)
            await response.write_eof()
        except ConnectionResetError:
            upstream_response.close()
        return response


async def session_context(app):
    async with ClientSession(
        auto_decompress=False,
        skip_auto_headers=("User-Agent", "Accept-Encoding"),
        timeout=ClientTimeout(total=None, sock_connect=30),
    ) as session:
        app["session"] = session
        yield


app = web.Application(client_max_size=0)
app.cleanup_ctx.append(session_context)
app.router.add_route("*", "/{path:.*}", handle)
web.run_app(app, host=host, port=port, access_log=None, print=None)
