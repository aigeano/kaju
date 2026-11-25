# Copyright 2026 Sagar Pandey. Licensed under the Apache License 2.0; see LICENSE and NOTICE.
"""kaju's iTerm2 helper.

kaju starts this script when iTerm2 is running and talks to it over stdio,
one JSON object per line. It uses iTerm2's Python API (the `iterm2` package,
GPL-2.0-or-later, installed separately) to find sessions, read the screen,
and type into a session. It also adds the right-click item "Comment with kaju".

Requests (kaju -> helper): {"id": n, "op": ..., ...}; replies: {"id": n, "ok": true, ...}
Events (helper -> kaju): {"event": "ready"} and {"event": "menu", "session": id}
"""
import asyncio
import json
import sys
import time

import iterm2

PASTE_START, PASTE_END = "\x1b[200~", "\x1b[201~"


def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


async def main(connection):
    app = await iterm2.async_get_app(connection)

    def session_of(req):
        s = app.get_session_by_id(req.get("session", ""))
        if s is None:
            raise LookupError("no such session")
        return s

    async def window_frame(s):
        f = await s.tab.window.async_get_frame()
        return [f.origin.x, f.origin.y, f.size.width, f.size.height]

    async def handle(req):
        op = req.get("op")
        if op == "front":
            await app.async_refresh_focus()
            w = app.current_terminal_window
            s = w and w.current_tab and w.current_tab.current_session
            if s is None:
                return {"session": None}
            return {"session": s.session_id, "tty": await s.async_get_variable("tty"),
                    "name": (s.name or "").strip(), "frame": await window_frame(s)}
        if op == "info":
            s = session_of(req)
            return {"tty": await s.async_get_variable("tty"), "name": (s.name or "").strip()}
        if op == "screen":
            s = session_of(req)
            screen = await s.async_get_screen_contents()
            lines = [screen.line(i).string for i in range(screen.number_of_lines)]
            win = await s.tab.window.async_get_frame()
            f = s.frame
            return {"lines": lines,
                    "area": [win.origin.x + f.origin.x, win.origin.y + f.origin.y, f.size.width, f.size.height],
                    "cols": s.grid_size.width, "rows": s.grid_size.height}
        if op == "frame":
            return {"frame": await window_frame(session_of(req))}
        if op == "selected":
            s = session_of(req)
            tab = s.tab.window.current_tab if s.tab and s.tab.window else None
            return {"selected": bool(tab) and tab.tab_id == s.tab.tab_id}
        if op == "activate":
            await session_of(req).async_activate(select_tab=True, order_window_front=True)
            return {}
        if op == "send":
            if time.time() > req.get("deadline", float("inf")):
                raise TimeoutError("send arrived after its deadline; not typed")
            s = session_of(req)
            await s.async_send_text(PASTE_START + req["text"] + PASTE_END)
            if req.get("submit"):
                await asyncio.sleep(0.2)
                await s.async_send_text("\r")
            return {}
        raise ValueError(f"unknown op {op}")

    async def serve(req):
        try:
            reply = await handle(req)
            emit(dict(reply, id=req.get("id"), ok=True))
        except Exception as e:  # report every failure to kaju instead of dying
            emit({"id": req.get("id"), "ok": False, "error": str(e)})

    @iterm2.ContextMenuProviderRPC
    async def comment_with_kaju(session_id=iterm2.Reference("id")):
        emit({"event": "menu", "session": session_id})  # return at once; kaju shows the input

    await comment_with_kaju.async_register(connection, "Comment with kaju", "io.github.aigeano.kaju.comment")

    loop = asyncio.get_event_loop()
    reader = asyncio.StreamReader()
    await loop.connect_read_pipe(lambda: asyncio.StreamReaderProtocol(reader), sys.stdin)
    emit({"event": "ready"})
    while True:
        line = await reader.readline()
        if not line:
            loop.stop()  # kaju went away
            return
        try:
            req = json.loads(line)
        except ValueError:
            continue
        loop.create_task(serve(req))


iterm2.run_forever(main)
