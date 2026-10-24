"""Per-user trading bot: scan -> open a risk-sized basket -> manage -> close -> rescan.

Everything the bot does is reported to the Spring backend through /internal/events,
which persists it and sends emails.
"""
import asyncio
import time
import uuid
from collections import deque
from datetime import datetime, timezone
import httpx
from . import news, risk
from .analysis import analyze_full, quick_rank, TF_ORDER
from .config import DEFAULT_CFG, BACKEND_URL, INTERNAL_KEY, GRAN, GOLD, DERIV_SYMBOL_KEY
from .deriv import account_ws, DerivError
from .indicators import atr
from .market import is_synthetic


async def emit(user_id, typ, data):
    for attempt in range(3):
        try:
            async with httpx.AsyncClient(timeout=10) as c:
                await c.post(f"{BACKEND_URL}/internal/events", headers={"X-Internal-Key": INTERNAL_KEY},
                             json={"userId": user_id, "type": typ, "data": data})
            return
        except Exception:
            await asyncio.sleep(1 + attempt)


def now_iso():
    return datetime.now(timezone.utc).isoformat()


class Basket:
    def __init__(self, symbol, direction, kind, score, reason):
        self.id = uuid.uuid4().hex[:12]
        self.symbol, self.direction, self.kind, self.score, self.reason = symbol, direction, kind, score, reason
        self.stake, self.realized, self.opened = 0.0, 0.0, time.time()
        self.open, self.closing = set(), False


class BotSession:
    def __init__(self, user_id, account_id, account_type, token, app_id, config, market):
        self.user_id, self.account_id, self.account_type = user_id, account_id, (account_type or "DEMO").upper()
        self.cfg = {**DEFAULT_CFG, **(config or {})}
        self.market = market
        self.ws = account_ws(account_id, token, app_id)
        self.running, self.halted, self.task = False, None, None
        self.balance, self.currency, self.peak = None, "USD", None
        self.day, self.day_start, self.day_pnl = None, None, 0.0
        self.baskets, self.contracts = {}, {}
        self.loss_streak, self.cooldown_until = 0, 0.0
        self.logs, self.top, self.last_scan, self.phase = deque(maxlen=200), [], None, "starting"
        self.gold_state, self._last_state_push = {}, 0.0

    # ---------- lifecycle ----------
    def log(self, msg, level="info"):
        self.logs.append({"t": now_iso(), "level": level, "msg": msg})

    async def start(self):
        if self.account_type == "REAL" and not self.cfg.get("allow_real"):
            raise PermissionError("Real-account trading is disabled. Test on a demo account first, "
                                  "then enable 'allow real account' in bot settings.")
        self.running = True
        self.task = asyncio.create_task(self._run())

    async def stop(self, close_open=False):
        self.running = False
        if close_open:
            for b in list(self.baskets.values()):
                await self.close_basket(b, "bot stopped by user")
        if self.task:
            self.task.cancel()
            try:
                await self.task
            except (asyncio.CancelledError, Exception):
                pass
        await self.ws.stop()
        self.phase = "stopped"
        await emit(self.user_id, "bot_state", {"running": False, "reason": "stopped"})

    def update_config(self, cfg):
        self.cfg.update({k: v for k, v in (cfg or {}).items() if k in DEFAULT_CFG and k != "allow_real"})

    async def _run(self):
        try:
            await self._init()
            last_scan = 0.0
            await emit(self.user_id, "bot_state", {"running": True})
            while self.running:
                try:
                    await self._housekeeping()
                    if self.cfg["news_gold"]:
                        await self._gold_news()
                    if time.time() - last_scan >= self.cfg["scan_interval"]:
                        last_scan = time.time()
                        await self._scan()
                except asyncio.CancelledError:
                    raise
                except Exception as e:
                    self.log(f"loop error: {e}", "error")
                await asyncio.sleep(5)
        except asyncio.CancelledError:
            pass
        except Exception as e:
            self.log(f"bot crashed: {e}", "error")
            self.running = False
            await emit(self.user_id, "bot_state", {"running": False, "reason": f"error: {e}"})

    async def _init(self):
        m = await self.ws.request({"balance": 1})
        self._set_balance(m.get("balance", {}))
        await self.ws.subscribe("balance", {"balance": 1}, lambda msg: self._set_balance(msg.get("balance", {})))
        try:
            pf = await self.ws.request({"portfolio": 1})
            for c in pf.get("portfolio", {}).get("contracts", []):
                await self._adopt(c)
        except Exception as e:
            self.log(f"portfolio check failed: {e}", "warn")
        self.log(f"connected to {self.account_type} account {self.account_id}, balance {self.balance} {self.currency}")

    def _set_balance(self, b):
        if not b or b.get("balance") is None:
            return
        self.balance = float(b["balance"])
        self.currency = b.get("currency", self.currency)
        self.peak = max(self.peak or 0, self.balance)

    async def _adopt(self, c):
        cid = c.get("contract_id")
        if not cid or cid in self.contracts:
            return
        b = Basket(c.get("symbol") or c.get("underlying_symbol") or "?", "?", "ADOPTED", 0, "found open on account at start")
        b.stake = float(c.get("buy_price", 0))
        b.open.add(cid)
        self.baskets[b.id] = b
        self.contracts[cid] = {"id": cid, "basket": b.id, "buy_price": b.stake, "profit": 0.0, "open": True}
        await self.ws.subscribe(f"poc:{cid}", {"proposal_open_contract": 1, "contract_id": cid}, self._on_poc)
        self.log(f"adopted existing contract {cid}")

    # ---------- housekeeping ----------
    async def _housekeeping(self):
        today = datetime.now(timezone.utc).date()
        if self.day != today and self.balance is not None:
            self.day, self.day_start, self.day_pnl = today, self.balance, 0.0
            if self.halted == "daily loss limit":
                self.halted = None
                self.log("new day: daily loss halt lifted")
        if self.peak and self.balance is not None and \
                self.balance < self.peak * (1 - self.cfg["max_drawdown_pct"] / 100):
            self.log(f"KILL SWITCH: balance {self.balance} is {self.cfg['max_drawdown_pct']}% below peak {self.peak}", "error")
            await emit(self.user_id, "halt", {"reason": "max drawdown kill switch", "balance": self.balance})
            await self.stop(close_open=True)
            return
        for b in list(self.baskets.values()):
            await self._check_basket(b)
        if time.time() - self._last_state_push > 30:
            self._last_state_push = time.time()
            await emit(self.user_id, "balance", {"balance": self.balance, "currency": self.currency,
                                                  "dayPnl": round(self.day_pnl, 2)})

    def _can_trade(self):
        return (self.running and not self.halted and self.balance is not None and time.time() >= self.cooldown_until
                and not self.baskets)

    # ---------- scanning ----------
    async def _scan(self):
        if not self._can_trade():
            self.phase = "managing positions" if self.baskets else ("paused: " + str(self.halted or "cooldown"))
            return
        self.phase = "scanning market"
        syms = await self.market.tradable(self.cfg["include_synthetics"])

        async def q(s):
            try:
                df = await self.market.candles(s, GRAN["H1"], 250)
                return quick_rank(df)[0], s
            except Exception:
                return 0.0, s
        ranked = sorted(await asyncio.gather(*[q(s) for s in syms]), reverse=True)
        cands = [s for sc, s in ranked if sc >= 1][:6]
        best, summaries = None, []
        for s in cands:
            try:
                r = analyze_full(await self.market.frames(s, TF_ORDER))
            except Exception:
                continue
            thr = self.cfg["threshold_synth"] if is_synthetic(s) else self.cfg["threshold_forex"]
            summaries.append({"symbol": s, "score": r["best_score"], "threshold": thr, "note": r["note"], "bias": r["bias"]})
            sig = r["signal"]
            if sig and sig["score"] >= thr and (best is None or sig["score"] > best[1]["score"]):
                best = (s, sig)
        self.top, self.last_scan = summaries, now_iso()
        self.phase = "watching - no clean entry" if not best else "entry found"
        self.log(f"scan of {len(syms)} symbols: {len(cands)} candidates, " +
                 (f"best {best[0]} score {best[1]['score']}" if best else "nothing meets the entry threshold"))
        if best:
            s, sig = best
            ev = await news.blackout(s, self.cfg["news_blackout_before"], self.cfg["news_blackout_after"])
            if ev:
                self.log(f"skip {s}: high-impact news {ev['title']} ({ev['currency']})")
                return
            await self.open_basket(s, sig, "AUTO")

    # ---------- trading ----------
    async def _proposal(self, symbol, ctype, stake, dur):
        m = await self.ws.request({"proposal": 1, "amount": stake, "basis": "stake", "contract_type": ctype,
                                   "currency": self.currency, "duration": dur, "duration_unit": "m",
                                   DERIV_SYMBOL_KEY: symbol})
        return m["proposal"]

    async def _proposal_find(self, symbol, ctype, stake, durs):
        last = None
        for d in durs:
            try:
                return await self._proposal(symbol, ctype, stake, d), d
            except DerivError as e:
                last = e
        raise last or DerivError("NoDuration", "no valid duration")

    async def open_basket(self, symbol, sig, kind):
        plan, why = risk.plan_basket(self.balance, sum(b.stake for b in self.baskets.values()), self.cfg, sig["score"], kind)
        if not plan:
            self.log(f"skip {symbol}: {why}")
            return
        ctype = "CALL" if sig["direction"] == "BUY" else "PUT"
        b = Basket(symbol, sig["direction"], kind, sig["score"], "; ".join(sig.get("reasons", []))[:900])
        self.baskets[b.id] = b
        dur, bought = None, 0
        for _ in range(plan["n"]):
            try:
                if dur is None:
                    prop, dur = await self._proposal_find(symbol, ctype, plan["stake"], sig.get("durations") or [15, 30, 60, 120])
                    if float(prop["payout"]) / float(prop["ask_price"]) < 1.6:
                        self.log(f"skip {symbol}: payout too low ({prop['payout']}/{prop['ask_price']})")
                        break
                else:
                    prop = await self._proposal(symbol, ctype, plan["stake"], dur)
                buy = (await self.ws.request({"buy": prop["id"], "price": float(prop["ask_price"])}))["buy"]
                cid, price = buy["contract_id"], float(buy["buy_price"])
                b.stake += price
                b.open.add(cid)
                self.contracts[cid] = {"id": cid, "basket": b.id, "buy_price": price, "profit": 0.0, "open": True}
                await self.ws.subscribe(f"poc:{cid}", {"proposal_open_contract": 1, "contract_id": cid}, self._on_poc)
                bought += 1
                await emit(self.user_id, "trade_open", {
                    "tradeRef": str(cid), "basketId": b.id, "accountId": self.account_id, "symbol": symbol,
                    "direction": sig["direction"], "kind": kind, "stake": price, "score": sig["score"],
                    "reason": b.reason, "durationMin": dur, "entry": sig.get("entry"), "sl": sig.get("sl"),
                    "tp": sig.get("tp1"), "openedAt": now_iso()})
            except Exception as e:
                self.log(f"buy failed on {symbol}: {e}", "error")
                break
        if bought == 0:
            self.baskets.pop(b.id, None)
            return
        self.phase = f"in trade: {symbol}"
        self.log(f"opened {kind} basket {b.id}: {bought} x {ctype} {symbol}, stake {plan['stake']} each (total {b.stake:.2f}), score {sig['score']}")

    async def _on_poc(self, msg):
        p = msg.get("proposal_open_contract")
        if not p:
            return
        cid = p.get("contract_id")
        c = self.contracts.get(cid)
        if not c or not c["open"]:
            return
        c["profit"] = float(p.get("profit") or 0)
        if p.get("is_sold") in (1, True) or p.get("status") in ("won", "lost", "sold"):
            await self._on_closed(cid, p)
        else:
            b = self.baskets.get(c["basket"])
            if b:
                await self._check_basket(b)

    async def _on_closed(self, cid, p):
        c = self.contracts.get(cid)
        if not c or not c["open"]:
            return
        c["open"] = False
        profit = float(p.get("profit") or 0)
        self.day_pnl += profit
        b = self.baskets.get(c["basket"])
        self.ws.unsubscribe(f"poc:{cid}")
        await emit(self.user_id, "trade_close", {"tradeRef": str(cid), "profit": profit, "sellPrice": p.get("sell_price"),
                                                  "status": p.get("status", "sold"), "closedAt": now_iso()})
        if b:
            b.open.discard(cid)
            b.realized += profit
            if not b.open:
                await self._basket_done(b)

    async def _basket_done(self, b):
        self.baskets.pop(b.id, None)
        self.loss_streak = self.loss_streak + 1 if b.realized < 0 else 0
        self.log(f"basket {b.id} {b.symbol} closed: P/L {b.realized:+.2f} on stake {b.stake:.2f}")
        await emit(self.user_id, "basket_close", {"basketId": b.id, "symbol": b.symbol, "pnl": round(b.realized, 2), "stake": round(b.stake, 2)})
        if self.loss_streak >= self.cfg["loss_streak_cooldown"]:
            self.cooldown_until = time.time() + self.cfg["cooldown_minutes"] * 60
            self.loss_streak = 0
            self.log(f"{self.cfg['loss_streak_cooldown']} losing baskets in a row: pausing {self.cfg['cooldown_minutes']} min", "warn")
        if self.day_start and self.day_pnl <= -self.day_start * self.cfg["daily_loss_pct"] / 100:
            self.halted = "daily loss limit"
            self.log(f"daily loss limit reached ({self.day_pnl:.2f}); no new trades today", "warn")
            await emit(self.user_id, "halt", {"reason": "daily loss limit", "dayPnl": round(self.day_pnl, 2), "balance": self.balance})
        self.phase = "watching"

    async def _check_basket(self, b):
        if b.closing:
            return
        pnl = b.realized + sum(self.contracts[c]["profit"] for c in b.open if c in self.contracts)
        if b.stake > 0:
            if pnl >= b.stake * self.cfg["tp_pct"] / 100:
                return await self.close_basket(b, f"take profit ({pnl:+.2f})")
            if pnl <= -b.stake * self.cfg["sl_pct"] / 100:
                return await self.close_basket(b, f"basket stop ({pnl:+.2f})")
        if b.kind != "NEWS":
            ev = await news.blackout(b.symbol, self.cfg["news_blackout_before"], 0)
            if ev:
                await self.close_basket(b, f"high-impact news ahead: {ev['title']}")

    async def close_basket(self, b, reason):
        if b.closing:
            return
        b.closing = True
        self.log(f"closing basket {b.id} ({b.symbol}): {reason}")

        async def sell(cid):
            try:
                r = (await self.ws.request({"sell": cid, "price": 0}))["sell"]
                sold = float(r.get("sold_for", 0))
                await self._on_closed(cid, {"profit": sold - self.contracts[cid]["buy_price"], "sell_price": sold, "status": "sold"})
            except Exception as e:
                self.log(f"sell {cid} failed (will expire): {e}", "warn")
        await asyncio.gather(*[sell(c) for c in list(b.open)])
        b.closing = False

    # ---------- gold NFP news trader ----------
    async def _gold_news(self):
        ev = await news.next_nfp()
        if not ev:
            return
        now = datetime.now(timezone.utc)
        dt = (ev["time"] - now).total_seconds()
        st = self.gold_state.setdefault(ev["epoch"], {"pre": None, "traded": False})
        if 0 < dt <= 900 and st["pre"] is None:
            r = analyze_full(await self.market.frames(GOLD, TF_ORDER))
            st["pre"] = r["bias"]
            self.log(f"NFP in {int(dt/60)} min - gold pre-news analysis: {r['bias']}")
        if -600 <= dt <= 0 and not st["traded"]:
            if not self._can_trade() or st["pre"] is None:
                return
            df = await self.market.candles(GOLD, 60, 120)
            after = df[df.time >= ev["epoch"]]
            if len(after) < 2:
                return
            a = float(atr(df[df.time < ev["epoch"]]).iloc[-1])
            move = float(df.close.iloc[-2] - after.open.iloc[0])
            d = 1 if move > 0 else -1
            pre_dir = {"bullish": 1, "bearish": -1}.get(st["pre"]["H4"], 0)
            thr = 1.6 if pre_dir == -d else 1.0
            if abs(move) >= thr * a and abs(move) <= 5 * a and (df.close.iloc[-2] - df.open.iloc[-2]) * d > 0:
                st["traded"] = True
                sig = {"direction": "BUY" if d == 1 else "SELL", "score": 80, "durations": [5, 10, 15, 30],
                       "reasons": [f"NFP reaction: gold moved {move:+.2f} ({abs(move)/a:.1f}x M1 ATR) after release",
                                   f"pre-news H4 bias {st['pre']['H4']}"]}
                await self.open_basket(GOLD, sig, "NEWS")
        elif dt < -600:
            st["traded"] = True

    # ---------- state for the app ----------
    def state(self):
        baskets = []
        for b in self.baskets.values():
            pnl = b.realized + sum(self.contracts[c]["profit"] for c in b.open if c in self.contracts)
            baskets.append({"id": b.id, "symbol": b.symbol, "direction": b.direction, "kind": b.kind, "stake": round(b.stake, 2),
                            "pnl": round(pnl, 2), "contracts": len(b.open), "score": b.score, "ageSec": int(time.time() - b.opened)})
        return {"running": self.running, "phase": self.phase, "halted": self.halted, "accountType": self.account_type,
                "balance": self.balance, "currency": self.currency, "dayPnl": round(self.day_pnl, 2),
                "cooldownSec": max(0, int(self.cooldown_until - time.time())), "baskets": baskets, "candidates": self.top,
                "lastScan": self.last_scan, "logs": list(self.logs)[-40:], "config": self.cfg}
