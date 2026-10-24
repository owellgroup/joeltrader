import asyncio
import logging
import time
from contextlib import asynccontextmanager
from fastapi import FastAPI, Header, HTTPException, Depends
from pydantic import BaseModel
from . import news
from .analysis import analyze_full, overlay, TF_ORDER
from .bot import BotSession, emit
from .config import INTERNAL_KEY, GRAN, DEFAULT_CFG
from .market import Market, is_synthetic

logging.basicConfig(level=logging.INFO)
market = Market()
bots: dict[int, BotSession] = {}
watchers: dict[int, list[str]] = {}
last_signal: dict[tuple, float] = {}


def auth(x_internal_key: str = Header(default="")):
    if x_internal_key != INTERNAL_KEY:
        raise HTTPException(401, "bad internal key")


async def watcher_loop():
    """Scans the symbols each user picked and pushes a signal event for clean setups."""
    while True:
        await asyncio.sleep(180)
        for uid, syms in list(watchers.items()):
            for s in syms:
                try:
                    r = analyze_full(await market.frames(s, TF_ORDER))
                    sig = r["signal"]
                    thr = DEFAULT_CFG["threshold_synth"] if is_synthetic(s) else DEFAULT_CFG["threshold_forex"]
                    key = (uid, s, sig and sig["direction"])
                    if sig and sig["score"] >= thr and time.time() - last_signal.get(key, 0) > 4 * 3600:
                        last_signal[key] = time.time()
                        await emit(uid, "signal", {"symbol": s, "tf": "M5", "bias": r["bias"], **sig})
                except Exception as e:
                    logging.warning("watcher %s: %s", s, e)


@asynccontextmanager
async def lifespan(app):
    market.ws.start()
    await market.start_quotes()
    task = asyncio.create_task(watcher_loop())
    yield
    task.cancel()
    for b in list(bots.values()):
        await b.stop(close_open=False)


app = FastAPI(title="joelTrader engine", lifespan=lifespan, dependencies=[Depends(auth)])


class StartReq(BaseModel):
    userId: int
    accountId: str
    accountType: str = "DEMO"
    token: str
    appId: str | None = None
    config: dict = {}


class StopReq(BaseModel):
    userId: int
    closeOpen: bool = False


class WatchReq(BaseModel):
    userId: int
    symbols: list[str]


@app.get("/health")
async def health():
    return {"ok": True, "bots": len(bots)}


@app.get("/symbols")
async def symbols():
    return await market.symbols()


@app.get("/quotes")
async def quotes(extra: str = ""):
    for s in [x for x in extra.split(",") if x]:
        await market.watch(s)
    return list(market.quotes.values())


@app.get("/candles")
async def candles(symbol: str, tf: str = "M15", count: int = 300):
    df = await market.candles(symbol, GRAN[tf], min(count, 1000))
    return df.to_dict("records")


@app.get("/analyze")
async def analyze(symbol: str, tf: str = "M15", auto: bool = False):
    df = await market.candles(symbol, GRAN[tf], 300)
    out = {"symbol": symbol, "tf": tf, "candles": df.to_dict("records"), "overlay": overlay(df, tf)}
    if auto:
        out["analysis"] = analyze_full(await market.frames(symbol, TF_ORDER))
    return out


@app.get("/calendar")
async def calendar():
    return news.public(await news.events())


@app.post("/bots/start")
async def bot_start(r: StartReq):
    if r.userId in bots:
        await bots[r.userId].stop(close_open=False)
    b = BotSession(r.userId, r.accountId, r.accountType, r.token, r.appId, r.config, market)
    try:
        await b.start()
    except PermissionError as e:
        raise HTTPException(403, str(e))
    bots[r.userId] = b
    return {"started": True}


@app.post("/bots/stop")
async def bot_stop(r: StopReq):
    b = bots.pop(r.userId, None)
    if b:
        await b.stop(close_open=r.closeOpen)
    return {"stopped": bool(b)}


@app.get("/bots")
async def bot_list():
    return [uid for uid, b in bots.items() if b.running]


@app.get("/bots/{uid}")
async def bot_state(uid: int):
    b = bots.get(uid)
    return b.state() if b else {"running": False, "phase": "stopped", "baskets": [], "candidates": [], "logs": [], "config": DEFAULT_CFG}


@app.post("/bots/{uid}/config")
async def bot_config(uid: int, body: dict):
    if uid in bots:
        bots[uid].update_config(body)
    return {"ok": True}


@app.post("/watch")
async def watch(r: WatchReq):
    watchers[r.userId] = r.symbols
    return {"watching": r.symbols}
