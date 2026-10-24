"""Multi-timeframe confluence analysis.

A setup is only reported when a higher-timeframe bias, an H1 zone (order block /
support-resistance / Fibonacci) and a lower-timeframe trigger all agree.
The score measures confluence, NOT a probability of winning.
"""
import numpy as np
from .indicators import ema, rsi, atr, bollinger, macd
from .market import is_synthetic
from .structure import swings, structure_trend, sr_levels, trendlines, order_blocks, fib

TF_ORDER = ["D1", "H4", "H1", "M15", "M5"]


def f(x):
    return None if x is None or (isinstance(x, float) and np.isnan(x)) else float(x)


def ctx(df):
    c = df.close
    e20, e50, e200 = ema(c, 20), ema(c, 50), ema(c, 200)
    a = atr(df)
    ml, ms, mh = macd(c)
    bu, bm, bl = bollinger(c)
    sh, sl = swings(df, 3)
    st = structure_trend(sh, sl)
    last = float(c.iloc[-1])
    ed = 0
    if len(df) >= 60:
        if last > e50.iloc[-1] > e200.iloc[-1]:
            ed = 1
        elif last < e50.iloc[-1] < e200.iloc[-1]:
            ed = -1
    s = st + ed
    bias = 1 if s >= 1 else -1 if s <= -1 else 0
    av = float(a.iloc[-1])
    return {"df": df, "ema20": e20, "ema50": e50, "ema200": e200, "atr_s": a, "atr": av,
            "rsi": rsi(c), "macd_h": mh, "bb": (bu, bm, bl), "sh": sh, "sl": sl, "struct": st,
            "bias": bias, "sr": sr_levels(df, sh, sl, av), "tl": trendlines(df, sh, sl),
            "obs": order_blocks(df, a), "fib": fib(sh, sl), "last": last}


def zones_for(d, price, h1):
    a = h1["atr"]
    names, lo, hi = [], [], []
    for ob in h1["obs"]:
        if (ob["type"] == "bullish") == (d == 1) and ob["low"] - 0.3 * a <= price <= ob["high"] + 0.3 * a:
            names.append("H1 order block")
            lo.append(ob["low"])
            hi.append(ob["high"])
    for lv in h1["sr"]:
        if abs(price - lv["price"]) <= 0.4 * a:
            names.append(f"H1 {lv['type']} ({lv['touches']} touches)")
            lo.append(lv["price"] - 0.15 * a)
            hi.append(lv["price"] + 0.15 * a)
    fb = h1["fib"]
    if fb and ((d == 1 and fb["direction"] == "up") or (d == -1 and fb["direction"] == "down")):
        a1, b1 = fb["levels"]["0.5"], fb["levels"]["0.786"]
        zl, zh = min(a1, b1), max(a1, b1)
        if zl - 0.2 * a <= price <= zh + 0.2 * a:
            names.append("H1 Fibonacci 50-78.6% retracement")
            lo.append(zl)
            hi.append(zh)
    return names, lo, hi


def trigger(d, df):
    if len(df) < 30:
        return None
    o, h, l, c = df.open.values, df.high.values, df.low.values, df.close.values
    i = -2  # last CLOSED candle (the final one is still forming)
    body = abs(c[i] - o[i])
    rng = h[i] - l[i] + 1e-12
    if d == 1:
        bull = c[i] > o[i]
        engulf = bull and c[i - 1] < o[i - 1] and c[i] >= o[i - 1] and o[i] <= c[i - 1]
        pin = (min(o[i], c[i]) - l[i]) > 2 * body and (c[i] - l[i]) / rng > 0.6
        brk = bull and c[i] > max(h[i - 1], h[i - 2])
        return "bullish engulfing" if engulf else "bullish pin bar" if pin else "bullish momentum close" if brk else None
    bear = c[i] < o[i]
    engulf = bear and c[i - 1] > o[i - 1] and c[i] <= o[i - 1] and o[i] >= c[i - 1]
    pin = (h[i] - max(o[i], c[i])) > 2 * body and (h[i] - c[i]) / rng > 0.6
    brk = bear and c[i] < min(l[i - 1], l[i - 2])
    return "bearish engulfing" if engulf else "bearish pin bar" if pin else "bearish momentum close" if brk else None


def evaluate(d, C):
    """Score one direction. C = dict of timeframe -> ctx. Returns dict or None with reason."""
    why = []
    d1, h4, h1, m15, m5 = (C[k] for k in TF_ORDER)
    if d1["bias"] == -d or h4["bias"] == -d:
        return {"score": 0, "reasons": ["higher timeframe bias opposes this direction"], "valid": False}
    score = 0
    score += 15 if d1["bias"] == d else 5
    score += 15 if h4["bias"] == d else 5
    score += 5 if h1["bias"] == d else 0
    score += 5 if m15["bias"] == d else 0
    word = "bullish" if d == 1 else "bearish"
    why.append(f"D1 {'aligned' if d1['bias'] == d else 'neutral'}, H4 {'aligned' if h4['bias'] == d else 'neutral'} ({word} bias)")
    price = m5["last"]
    zn, zlo, zhi = zones_for(d, price, h1)
    if not zn:
        return {"score": score, "reasons": why + ["price is not at an H1 zone"], "valid": False}
    score += 30 if len(zn) >= 2 else 20
    why.append("zone confluence: " + ", ".join(zn))
    trg = trigger(d, m5["df"])
    if not trg:
        return {"score": score, "reasons": why + ["waiting for an M5 trigger candle"], "valid": False}
    score += 10
    why.append(f"M5 trigger: {trg}")
    score += _extras(d, m5, why)
    for t in m15["tl"]:
        if not t["broken"] and abs(price - t["proj"]) <= 0.5 * m15["atr"] and \
                ((d == 1 and t["type"] == "support") or (d == -1 and t["type"] == "resistance")):
            score += 5; why.append(f"M15 trendline {t['type']} touch"); break
    # risk levels
    a15 = m15["atr"]
    ldf = m5["df"]
    if d == 1:
        sl = min(min(zlo), float(ldf.low.iloc[-7:].min())) - 0.3 * a15
        risk = price - sl
        cands = sorted([lv["price"] for lv in h1["sr"] if lv["price"] > price] +
                       [ob["low"] for ob in h1["obs"] if ob["type"] == "bearish" and ob["low"] > price])
        tp_ok = [x for x in cands if risk > 0 and (x - price) / risk >= 1.5]
    else:
        sl = max(max(zhi), float(ldf.high.iloc[-7:].max())) + 0.3 * a15
        risk = sl - price
        cands = sorted([lv["price"] for lv in h1["sr"] if lv["price"] < price] +
                       [ob["high"] for ob in h1["obs"] if ob["type"] == "bullish" and ob["high"] < price], reverse=True)
        tp_ok = [x for x in cands if risk > 0 and (price - x) / risk >= 1.5]
    if risk <= 0 or risk > 4 * a15:
        return {"score": score, "reasons": why + ["stop distance invalid or too wide"], "valid": False}
    tp1 = tp_ok[0] if tp_ok else price + d * 2 * risk
    if not tp_ok and not (d1["bias"] == d and h4["bias"] == d):
        return {"score": score, "reasons": why + ["no target with at least 1.5R before opposing structure"], "valid": False}
    tp2 = price + d * max(3 * risk, abs(tp1 - price) * 1.5)
    return {"score": min(100, score), "reasons": why, "valid": True, "direction": "BUY" if d == 1 else "SELL",
            "entry": price, "sl": float(sl), "tp1": float(tp1), "tp2": float(tp2),
            "rr": round(abs(tp1 - price) / risk, 2), "zone": [float(min(zlo)), float(max(zhi))]}


def _extras(d, m5, why):
    """RSI / MACD / Bollinger confirmation. Returns points added."""
    score = 0
    r = m5["rsi"]
    if d == 1 and 30 <= r.iloc[-2] <= 65 and r.iloc[-2] > r.iloc[-3]:
        score += 5
        why.append("RSI rising from non-overbought zone")
    if d == -1 and 35 <= r.iloc[-2] <= 70 and r.iloc[-2] < r.iloc[-3]:
        score += 5
        why.append("RSI falling from non-oversold zone")
    mh = m5["macd_h"]
    if (d == 1 and mh.iloc[-2] > mh.iloc[-3]) or (d == -1 and mh.iloc[-2] < mh.iloc[-3]):
        score += 5
        why.append("MACD histogram turning with direction")
    bu, _, bl = m5["bb"]
    dfm = m5["df"]
    if d == 1 and (dfm.low.iloc[-4:-1] <= bl.iloc[-4:-1]).any() and dfm.close.iloc[-2] > bl.iloc[-2]:
        score += 5
        why.append("Bollinger lower-band rejection")
    if d == -1 and (dfm.high.iloc[-4:-1] >= bu.iloc[-4:-1]).any() and dfm.close.iloc[-2] < bu.iloc[-2]:
        score += 5
        why.append("Bollinger upper-band rejection")
    return score


def synth_kind(symbol):
    """boom / crash / vol / other, or None for forex and gold."""
    if not symbol or not is_synthetic(symbol):
        return None
    if symbol.startswith("BOOM"):
        return "boom"
    if symbol.startswith("CRASH"):
        return "crash"
    if symbol.startswith(("R_", "1HZ")):
        return "vol"
    return "other"


def evaluate_synth(d, C, kind):
    """Good entry for Boom, Crash and Volatility.

    These indices do not behave like forex: Volatility is often neutral on D1, and Boom/Crash
    spend most of their time drifting one way with a spike the other way. A setup still needs
    a pullback (or an H1 zone) and a closed M5 trigger. Boom prefers buys; Crash prefers sells.
    """
    why = []
    h4, h1, m15, m5 = C["H4"], C["H1"], C["M15"], C["M5"]
    if h1["bias"] == -d and h4["bias"] == -d:
        return {"score": 0, "reasons": ["H4 and H1 both oppose this direction"], "valid": False}
    score = 10
    word = "bullish" if d == 1 else "bearish"
    if kind == "boom" and d == 1:
        score += 15
        why.append("Boom drift: buy the pullback")
    elif kind == "crash" and d == -1:
        score += 15
        why.append("Crash drift: sell the rally")
    elif kind == "vol":
        score += 8
        why.append(f"Volatility index {word} setup")
    else:
        score += 5
        why.append(f"Synthetic {word} setup")
    if h1["bias"] == d:
        score += 10
        why.append("H1 bias aligned")
    elif h1["bias"] == 0:
        score += 4
        why.append("H1 bias neutral")
    if m15["bias"] == d:
        score += 8
        why.append("M15 bias aligned")
    price = m5["last"]
    a = h1["atr"] or m5["atr"] or 1e-9
    ema20, ema50 = float(h1["ema20"].iloc[-1]), float(h1["ema50"].iloc[-1])
    band_lo, band_hi = min(ema20, ema50), max(ema20, ema50)
    near_ema = (d == 1 and band_lo - 0.45 * a <= price <= band_hi + 0.45 * a) or \
               (d == -1 and band_lo - 0.45 * a <= price <= band_hi + 0.45 * a)
    m5_ema = float(m5["ema20"].iloc[-2])
    m5a = m5["atr"] or a
    bar_low = float(m5["df"].low.iloc[-2])
    bar_high = float(m5["df"].high.iloc[-2])
    bar_close = float(m5["df"].close.iloc[-2])
    m5_pull = (d == 1 and bar_low <= m5_ema + 0.45 * m5a and bar_close >= m5_ema) or \
              (d == -1 and bar_high >= m5_ema - 0.45 * m5a and bar_close <= m5_ema)
    zn, zlo, zhi = zones_for(d, price, h1)
    bu, _, bl = m5["bb"]
    dfm = m5["df"]
    band = (kind == "vol" and d == 1 and (dfm.low.iloc[-4:-1] <= bl.iloc[-4:-1]).any()) or \
           (kind == "vol" and d == -1 and (dfm.high.iloc[-4:-1] >= bu.iloc[-4:-1]).any())
    if not zn and not near_ema and not m5_pull and not band:
        return {"score": score, "reasons": why + ["not at a pullback or H1 zone"], "valid": False}
    if zn:
        score += 18 if len(zn) >= 2 else 12
        why.append("zone: " + ", ".join(zn))
    if near_ema or m5_pull:
        score += 12
        why.append("pullback into the moving average")
    if band:
        score += 8
        why.append("Volatility band touch")
    if not zlo:
        zlo, zhi = [price - 0.4 * a], [price + 0.4 * a]
    trg = trigger(d, m5["df"])
    if not trg:
        return {"score": score, "reasons": why + ["waiting for an M5 trigger candle"], "valid": False}
    score += 12
    why.append(f"M5 trigger: {trg}")
    score += _extras(d, m5, why)
    if d == 1:
        swing = float(m5["df"].low.iloc[-8:].min())
        sl = min(swing, min(zlo)) - 0.15 * m5a
        if price - sl <= 0 or price - sl > 2.5 * m5a:
            sl = price - 1.2 * m5a
    else:
        swing = float(m5["df"].high.iloc[-8:].max())
        sl = max(swing, max(zhi)) + 0.15 * m5a
        if sl - price <= 0 or sl - price > 2.5 * m5a:
            sl = price + 1.2 * m5a
    risk = abs(price - sl)
    if risk <= 0:
        return {"score": score, "reasons": why + ["stop distance invalid"], "valid": False}
    tp1 = price + d * 1.8 * risk
    tp2 = price + d * 2.6 * risk
    durs = [5, 10, 15, 30] if kind in ("boom", "crash") else [10, 15, 30, 60]
    return {"score": min(100, score), "reasons": why, "valid": True, "direction": "BUY" if d == 1 else "SELL",
            "entry": price, "sl": float(sl), "tp1": float(tp1), "tp2": float(tp2),
            "rr": 1.8, "zone": [float(min(zlo)), float(max(zhi))], "durations": durs}


def entry_threshold(symbol, cfg):
    """One good-entry bar. A saved higher synthetic threshold cannot block Boom, Crash or Volatility."""
    fx = float(cfg["threshold_forex"])
    if not is_synthetic(symbol):
        return fx
    return min(fx, float(cfg.get("threshold_synth", fx)))


def analyze_full(frames, symbol=None):
    """frames: dict TF -> DataFrame (D1,H4,H1,M15,M5). Returns bias map + best signal (or None)."""
    C = {k: ctx(frames[k]) for k in TF_ORDER}
    names = {1: "bullish", -1: "bearish", 0: "neutral"}
    bias = {k: names[C[k]["bias"]] for k in TF_ORDER}
    kind = synth_kind(symbol)
    if kind:
        buy, sell = evaluate_synth(1, C, kind), evaluate_synth(-1, C, kind)
    else:
        buy, sell = evaluate(1, C), evaluate(-1, C)
    best = max([buy, sell], key=lambda x: x["score"])
    sig = best if best.get("valid") else None
    return {"bias": bias, "signal": sig, "buy": buy, "sell": sell, "best_score": best["score"],
            "note": None if sig else (best["reasons"][-1] if best["reasons"] else "no setup"),
            "kind": kind or "forex"}


def quick_rank(df_h1, synthetic=False):
    """Cheap H1-only prefilter used to pick candidates before the full analysis."""
    c = ctx(df_h1)
    if synthetic:
        # Volatility is often neutral on H1. Rank the pullback instead of discarding it.
        ema = float(c["ema20"].iloc[-1])
        dist = abs(c["last"] - ema) / max(c["atr"], 1e-9)
        score = max(0.0, 2.2 - dist)
        if c["bias"] != 0:
            score += 0.8
        return score, c["bias"] or 1
    if c["bias"] == 0:
        return 0.0, 0
    zn, _, _ = zones_for(c["bias"], c["last"], c)
    return len(zn) + 0.1 * abs(c["struct"] + 1), c["bias"]


def overlay(df, tf):
    """Everything the chart page draws for one timeframe, aligned to df rows."""
    C = ctx(df)
    t = df.time.values
    n = len(df)

    def ser(s):
        return [f(x) for x in s.values]
    tls = []
    for x in C["tl"]:
        tls.append({"type": x["type"], "t1": int(t[x["i1"]]), "p1": x["p1"], "t2": int(t[min(x["i2"], n - 1)]),
                    "p2": x["p2"], "slope_per_bar": x["slope"], "broken": x["broken"]})
    return {
        "tf": tf, "bias": {1: "bullish", -1: "bearish", 0: "neutral"}[C["bias"]], "atr": C["atr"],
        "sr": [{"price": s["price"], "touches": s["touches"], "type": s["type"]} for s in C["sr"]],
        "trendlines": tls,
        "order_blocks": [{"type": o["type"], "t": int(t[o["i"]]), "low": o["low"], "high": o["high"]} for o in C["obs"]],
        "fib": None if not C["fib"] else {"direction": C["fib"]["direction"], "t_hi": int(t[C["fib"]["i_hi"]]),
                                           "t_lo": int(t[C["fib"]["i_lo"]]), "hi": C["fib"]["hi"],
                                           "lo": C["fib"]["lo"], "levels": C["fib"]["levels"]},
        "indicators": {"ema20": ser(C["ema20"]), "ema50": ser(C["ema50"]), "ema200": ser(C["ema200"]),
                       "bb_upper": ser(C["bb"][0]), "bb_mid": ser(C["bb"][1]), "bb_lower": ser(C["bb"][2]),
                       "rsi": ser(C["rsi"])},
    }
