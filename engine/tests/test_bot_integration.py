"""End-to-end bot lifecycle against a fake Deriv socket (no network)."""
import asyncio, json, itertools
import pytest, websockets
from app import bot as botmod
from app.bot import BotSession
from app.deriv import DerivWS
from app.market import Market

pytestmark = pytest.mark.asyncio
cid = itertools.count(1000)


def make_server(profit_ratio):
    contracts = {}

    async def handler(ws):
        async for raw in ws:
            m = json.loads(raw)
            rid = m["req_id"]
            out = {"req_id": rid}
            if "balance" in m:
                out["balance"] = {"balance": 1000.0, "currency": "USD"}
            elif "portfolio" in m:
                out["portfolio"] = {"contracts": []}
            elif "proposal" in m:
                out["proposal"] = {"id": "p", "ask_price": m["amount"], "payout": round(m["amount"] * 1.9, 2)}
            elif "buy" in m:
                c = next(cid)
                contracts[c] = m["price"]
                out["buy"] = {"contract_id": c, "buy_price": m["price"]}
            elif "proposal_open_contract" in m:
                c = m["contract_id"]
                out["proposal_open_contract"] = {"contract_id": c, "profit": 0, "is_sold": 0, "status": "open"}
                await ws.send(json.dumps(out))
                await asyncio.sleep(0.3)
                out = {"req_id": rid, "proposal_open_contract": {"contract_id": c, "profit": contracts[c] * profit_ratio,
                                                                 "is_sold": 0, "status": "open"}}
            elif "sell" in m:
                out["sell"] = {"contract_id": m["sell"], "sold_for": round(contracts[m["sell"]] * (1 + profit_ratio), 2)}
            await ws.send(json.dumps(out))
    return handler


async def run_case(profit_ratio):
    events = []

    async def fake_emit(uid, typ, data):
        events.append((typ, data))
    botmod.emit = fake_emit
    async with websockets.serve(make_server(profit_ratio), "127.0.0.1", 0) as srv:
        port = srv.sockets[0].getsockname()[1]

        async def provider():
            return f"ws://127.0.0.1:{port}"
        b = BotSession(1, "DOT1", "DEMO", "tok", "app", {}, Market())
        b.ws = DerivWS(provider, "fake")
        await b.start()
        await asyncio.sleep(0.5)
        sig = {"direction": "BUY", "score": 85, "reasons": ["test"], "entry": 1.1, "sl": 1.09, "tp1": 1.12, "durations": [15]}
        await b.open_basket("frxEURUSD", sig, "AUTO")
        assert len(b.baskets) == 1
        await asyncio.sleep(8)
        await b.stop()
    return b, events


async def test_take_profit_closes_basket():
    b, ev = await run_case(0.30)
    types = [t for t, _ in ev]
    assert types.count("trade_open") >= 1
    assert "trade_close" in types and "basket_close" in types
    assert not b.baskets
    assert all(d["profit"] > 0 for t, d in ev if t == "trade_close")


async def test_basket_stop_limits_loss():
    b, ev = await run_case(-0.60)
    closes = [d for t, d in ev if t == "trade_close"]
    assert closes and all(d["profit"] < 0 for d in closes)
    assert not b.baskets
