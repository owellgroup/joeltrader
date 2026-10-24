"""Market data over the public socket: candles (cached + throttled), symbols, live quotes."""
import asyncio
import time
import pandas as pd
from .deriv import public_ws

FALLBACK = ["frxEURUSD", "frxGBPUSD", "frxUSDJPY", "frxAUDUSD", "frxUSDCAD", "frxUSDCHF", "frxNZDUSD",
            "frxEURGBP", "frxEURJPY", "frxGBPJPY", "frxXAUUSD", "R_10", "R_25", "R_50", "R_75", "R_100",
            "1HZ10V", "1HZ25V", "1HZ50V", "1HZ75V", "1HZ100V",
            "CRASH300N", "CRASH500", "CRASH600", "CRASH900", "CRASH1000",
            "BOOM300N", "BOOM500", "BOOM600", "BOOM900", "BOOM1000"]
WATCH = ["frxEURUSD", "frxGBPUSD", "frxUSDJPY", "frxXAUUSD", "frxAUDUSD", "R_75", "1HZ75V", "BOOM1000", "CRASH1000"]
# R_75 / 1HZ75V = Volatility 75 (the index traders call VIX 75). Boom and Crash use the BOOM/CRASH codes.
SYNTH_PREFIX = ("R_", "1HZ", "BOOM", "CRASH", "JD", "stpRNG", "RDBEAR", "RDBULL", "WLD", "RB")
PRIORITY_SYNTH = ["R_75", "1HZ75V",
                  "BOOM300N", "BOOM500", "BOOM600", "BOOM900", "BOOM1000",
                  "CRASH300N", "CRASH500", "CRASH600", "CRASH900", "CRASH1000"]


def is_synthetic(sym, market=""):
    if (sym or "").startswith(SYNTH_PREFIX):
        return True
    m = (market or "").lower()
    return "synthetic" in m or m.startswith("random")


class Market:
    def __init__(self):
        self.ws = public_ws()
        self.cache, self._sym, self.quotes, self._open = {}, (0, []), {}, {}
        self._sem = asyncio.Semaphore(4)
        self._gate = asyncio.Lock()
        self._last = 0.0

    async def _throttle(self):
        async with self._gate:
            wait = 0.15 - (time.time() - self._last)
            if wait > 0:
                await asyncio.sleep(wait)
            self._last = time.time()

    async def candles(self, symbol, gran, count=250):
        key = (symbol, gran, count)
        ttl = 15 if gran <= 900 else 120 if gran <= 14400 else 600
        hit = self.cache.get(key)
        if hit and time.time() - hit[0] < ttl:
            return hit[1]
        async with self._sem:
            await self._throttle()
            msg = await self.ws.request({"ticks_history": symbol, "adjust_start_time": 1, "count": count,
                                         "end": "latest", "granularity": gran, "style": "candles"})
        df = pd.DataFrame(msg.get("candles", []))
        if df.empty:
            raise ValueError(f"no candles for {symbol}")
        df = df.rename(columns={"epoch": "time"})[["time", "open", "high", "low", "close"]].astype(float)
        df["time"] = df["time"].astype(int)
        df = df.reset_index(drop=True)
        self.cache[key] = (time.time(), df)
        return df

    async def frames(self, symbol, tfs, count=250):
        from .config import GRAN
        dfs = await asyncio.gather(*[self.candles(symbol, GRAN[t], count) for t in tfs])
        return dict(zip(tfs, dfs))

    async def symbols(self):
        if time.time() - self._sym[0] < 600 and self._sym[1]:
            return self._sym[1]
        out = []
        try:
            msg = await self.ws.request({"active_symbols": "brief", "product_type": "basic"})
            for it in msg.get("active_symbols", []):
                s = it.get("symbol") or it.get("underlying_symbol")
                if not s:
                    continue
                out.append({"symbol": s, "name": it.get("display_name", s), "market": it.get("market", ""),
                            "open": bool(it.get("exchange_is_open", 1)) and not it.get("is_trading_suspended", 0)})
        except Exception:
            out = []
        if not out:
            out = [{"symbol": s, "name": s, "market": "synthetic_index" if is_synthetic(s) else "forex", "open": True}
                   for s in FALLBACK]
        self._sym = (time.time(), out)
        return out

    async def tradable(self, include_synth=True):
        out, seen = [], set()
        for row in await self.symbols():
            sym = row["symbol"]
            synth = is_synthetic(sym, row.get("market", ""))
            if not row["open"] or sym in seen:
                continue
            if synth and not include_synth:
                continue
            if sym.startswith("frx") or synth:
                out.append(sym)
                seen.add(sym)
        # A partial active_symbols payload must not drop Boom, Crash or Volatility 75.
        if include_synth:
            for sym in PRIORITY_SYNTH:
                if sym not in seen:
                    out.append(sym)
                    seen.add(sym)
        return out

    async def start_quotes(self, symbols=WATCH):
        for s in symbols:
            await self.watch(s)

    async def watch(self, symbol):
        if symbol in self.quotes:
            return

        def cb(msg, sym=symbol):
            t = msg.get("tick")
            if not t:
                return
            q = float(t["quote"])
            self._open.setdefault(sym, q)
            self.quotes[sym] = {"symbol": sym, "price": q, "epoch": t.get("epoch"),
                                "change_pct": round((q - self._open[sym]) / self._open[sym] * 100, 4)}
        self.quotes[symbol] = {"symbol": symbol, "price": None, "epoch": None, "change_pct": 0}
        await self.ws.subscribe(f"tick:{symbol}", {"ticks": symbol}, cb)
