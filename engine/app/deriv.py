"""Deriv WebSocket client (auto-reconnect, req_id routing, subscriptions).

Account sockets authenticate by first calling REST
POST /trading/v1/options/accounts/{id}/otp (Bearer PAT + Deriv-App-ID header),
which returns a one-time wss URL (valid 120 s, single use).
A fresh OTP is requested on every (re)connect.
"""
import asyncio
import inspect
import itertools
import json
import logging
import httpx
import websockets
from .config import DERIV_REST, DERIV_WS_PUBLIC

log = logging.getLogger("deriv")


class DerivError(Exception):
    def __init__(self, code, message):
        super().__init__(f"{code}: {message}")
        self.code, self.message = code, message


class DerivWS:
    def __init__(self, url_provider, name="ws"):
        self._url_provider, self.name = url_provider, name
        self._ids = itertools.count(1)
        self._pending, self._subs, self._defs = {}, {}, {}
        self._ready = asyncio.Event()
        self._ws = None
        self._task = None

    def start(self):
        if self._task is None or self._task.done():
            self._task = asyncio.create_task(self._supervise())

    async def stop(self):
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except (asyncio.CancelledError, Exception):
                pass
            self._task = None

    async def _supervise(self):
        backoff = 1
        while True:
            try:
                url = await self._url_provider()
                async with websockets.connect(url, ping_interval=20, ping_timeout=20, max_size=16_000_000) as ws:
                    self._ws, backoff, self._subs = ws, 1, {}
                    self._ready.set()
                    log.info("%s connected", self.name)
                    for key, (req, cb) in list(self._defs.items()):
                        await self._send_sub(req, cb)
                    async for raw in ws:
                        self._dispatch(json.loads(raw))
            except asyncio.CancelledError:
                raise
            except Exception as e:
                log.warning("%s connection problem: %s", self.name, e)
            finally:
                self._ready.clear()
                self._ws = None
                for fut in self._pending.values():
                    if not fut.done():
                        fut.set_exception(ConnectionError("socket closed"))
                self._pending.clear()
            await asyncio.sleep(min(backoff, 30))
            backoff *= 2

    def _dispatch(self, msg):
        rid = msg.get("req_id")
        fut = self._pending.pop(rid, None)
        if fut is not None:
            if not fut.done():
                if msg.get("error"):
                    e = msg["error"]
                    fut.set_exception(DerivError(e.get("code"), e.get("message")))
                else:
                    fut.set_result(msg)
            return
        cb = self._subs.get(rid)
        if cb:
            res = cb(msg)
            if inspect.isawaitable(res):
                asyncio.ensure_future(res)

    async def request(self, req, timeout=20):
        self.start()
        await asyncio.wait_for(self._ready.wait(), 30)
        rid = next(self._ids)
        fut = asyncio.get_running_loop().create_future()
        self._pending[rid] = fut
        await self._ws.send(json.dumps({**req, "req_id": rid}))
        return await asyncio.wait_for(fut, timeout)

    async def _send_sub(self, req, cb):
        rid = next(self._ids)
        self._subs[rid] = cb
        await self._ws.send(json.dumps({**req, "req_id": rid, "subscribe": 1}))

    async def subscribe(self, key, req, cb):
        self.start()
        self._defs[key] = (req, cb)
        if self._ready.is_set():
            await self._send_sub(req, cb)

    def unsubscribe(self, key):
        d = self._defs.pop(key, None)
        if d:
            for rid, cb in list(self._subs.items()):
                if cb is d[1]:
                    self._subs.pop(rid, None)


def public_ws():
    async def provider():
        return DERIV_WS_PUBLIC
    return DerivWS(provider, "public")


def account_ws(account_id, token, app_id):
    async def provider():
        headers = {"Authorization": f"Bearer {token}"}
        if app_id:
            headers["Deriv-App-ID"] = str(app_id)
        async with httpx.AsyncClient(timeout=15) as c:
            r = await c.post(f"{DERIV_REST}/trading/v1/options/accounts/{account_id}/otp", headers=headers)
            r.raise_for_status()
            return r.json()["data"]["url"]
    return DerivWS(provider, f"acct-{account_id}")
