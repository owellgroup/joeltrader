"""Price-structure tools: swings, support/resistance, trendlines, order blocks, Fibonacci."""
import numpy as np


def swings(df, n=3):
    h, l = df.high.values, df.low.values
    sh, sl = [], []
    for i in range(n, len(df) - n):
        if h[i] >= h[i - n:i + n + 1].max() and h[i] > h[i - 1]:
            sh.append((i, float(h[i])))
        if l[i] <= l[i - n:i + n + 1].min() and l[i] < l[i - 1]:
            sl.append((i, float(l[i])))
    return sh, sl


def structure_trend(sh, sl):
    if len(sh) < 2 or len(sl) < 2:
        return 0
    hh, hl = sh[-1][1] > sh[-2][1], sl[-1][1] > sl[-2][1]
    lh, ll = sh[-1][1] < sh[-2][1], sl[-1][1] < sl[-2][1]
    if hh and hl:
        return 1
    if lh and ll:
        return -1
    return 0


def sr_levels(df, sh, sl, atr_val, max_levels=8):
    pts = sorted([(p, i) for i, p in sh + sl])
    if not pts or not atr_val or atr_val <= 0:
        return []
    clusters, cur = [], [pts[0]]
    for p in pts[1:]:
        if p[0] - np.mean([x[0] for x in cur]) <= 0.6 * atr_val:
            cur.append(p)
        else:
            clusters.append(cur)
            cur = [p]
    clusters.append(cur)
    close = float(df.close.values[-1])
    out = []
    for c in clusters:
        if len(c) < 2:
            continue
        price = float(np.mean([x[0] for x in c]))
        out.append({"price": price, "touches": len(c), "last_idx": int(max(x[1] for x in c)),
                    "type": "support" if price < close else "resistance"})
    out.sort(key=lambda x: (-x["touches"], abs(x["price"] - close)))
    return out[:max_levels]


def trendlines(df, sh, sl):
    res, last = [], len(df) - 1
    c = df.close.values
    if len(sl) >= 2:
        (i1, p1), (i2, p2) = sl[-2], sl[-1]
        if p2 > p1 and i2 - i1 >= 5:
            slope = (p2 - p1) / (i2 - i1)
            broken = bool(any(c[k] < p1 + slope * (k - i1) for k in range(i2 + 1, last + 1)))
            res.append({"type": "support", "i1": i1, "p1": p1, "i2": i2, "p2": p2, "slope": slope,
                        "proj": p2 + slope * (last - i2), "broken": broken})
    if len(sh) >= 2:
        (i1, p1), (i2, p2) = sh[-2], sh[-1]
        if p2 < p1 and i2 - i1 >= 5:
            slope = (p2 - p1) / (i2 - i1)
            broken = bool(any(c[k] > p1 + slope * (k - i1) for k in range(i2 + 1, last + 1)))
            res.append({"type": "resistance", "i1": i1, "p1": p1, "i2": i2, "p2": p2, "slope": slope,
                        "proj": p2 + slope * (last - i2), "broken": broken})
    return res


def order_blocks(df, atr_series, lookback=150, disp=1.5):
    o, c, h, l = df.open.values, df.close.values, df.high.values, df.low.values
    a = atr_series.values
    obs = []
    for i in range(max(2, len(df) - lookback), len(df)):
        body, ai = abs(c[i] - o[i]), a[i - 1]
        if np.isnan(ai) or body < disp * ai:
            continue
        if c[i] > o[i]:
            j = i - 1
            while j >= max(0, i - 5) and c[j] >= o[j]:
                j -= 1
            if j >= 0 and c[j] < o[j]:
                mit = bool((c[i + 1:] < l[j]).any())
                obs.append({"type": "bullish", "i": j, "low": float(l[j]), "high": float(h[j]), "mitigated": mit})
        else:
            j = i - 1
            while j >= max(0, i - 5) and c[j] <= o[j]:
                j -= 1
            if j >= 0 and c[j] > o[j]:
                mit = bool((c[i + 1:] > h[j]).any())
                obs.append({"type": "bearish", "i": j, "low": float(l[j]), "high": float(h[j]), "mitigated": mit})
    return [x for x in obs if not x["mitigated"]][-4:]


def fib(sh, sl):
    if not sh or not sl:
        return None
    ih, hi = sh[-1]
    il, lo = sl[-1]
    rng = hi - lo
    if rng <= 0:
        return None
    up = il < ih
    ratios = [0, 0.236, 0.382, 0.5, 0.618, 0.786, 1]
    levels = {str(r): (hi - rng * r if up else lo + rng * r) for r in ratios}
    return {"direction": "up" if up else "down", "hi": hi, "lo": lo, "i_hi": ih, "i_lo": il, "levels": levels}
