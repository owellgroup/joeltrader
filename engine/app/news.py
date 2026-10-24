"""Economic calendar (ForexFactory weekly JSON feed) + blackout checks."""
import time
from datetime import datetime, timezone, timedelta
import httpx
from .config import CALENDAR_URL

NFP_KEYS = ("non-farm employment change", "nonfarm payrolls", "non-farm payrolls")
_cache = {"t": 0, "events": []}


def symbol_currencies(symbol):
    if symbol.startswith("frx") and len(symbol) >= 9:
        return {symbol[3:6], symbol[6:9]}
    return set()


async def events(force=False):
    if not force and time.time() - _cache["t"] < 900 and _cache["events"]:
        return _cache["events"]
    try:
        async with httpx.AsyncClient(timeout=15) as c:
            r = await c.get(CALENDAR_URL)
            r.raise_for_status()
            out = []
            for e in r.json():
                try:
                    dt = datetime.fromisoformat(e["date"]).astimezone(timezone.utc)
                except Exception:
                    continue
                out.append({"title": e.get("title"), "currency": e.get("country"), "impact": e.get("impact"),
                            "time": dt, "epoch": int(dt.timestamp()), "forecast": e.get("forecast"),
                            "previous": e.get("previous")})
            out.sort(key=lambda x: x["time"])
            _cache.update(t=time.time(), events=out)
    except Exception:
        _cache["t"] = time.time() - 600  # retry in ~5 min, keep stale data
    return _cache["events"]


def public(evs):
    return [{**e, "time": e["time"].isoformat()} for e in evs]


async def blackout(symbol, before=30, after=15, now=None):
    """Return the high-impact event blocking this symbol right now, else None."""
    cur = symbol_currencies(symbol)
    if not cur:
        return None
    now = now or datetime.now(timezone.utc)
    for e in await events():
        if e["impact"] == "High" and e["currency"] in cur:
            if e["time"] - timedelta(minutes=before) <= now <= e["time"] + timedelta(minutes=after):
                return e
    return None


async def next_nfp(now=None, window_after=20):
    now = now or datetime.now(timezone.utc)
    for e in await events():
        if e["currency"] == "USD" and e["impact"] == "High" and any(k in (e["title"] or "").lower() for k in NFP_KEYS):
            if e["time"] + timedelta(minutes=window_after) >= now:
                return e
    return None
