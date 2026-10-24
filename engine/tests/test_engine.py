import numpy as np, pandas as pd, pytest
from app.analysis import analyze_full, entry_threshold, overlay, quick_rank, synth_kind, ctx, TF_ORDER
from app.market import is_synthetic
from app.risk import plan_basket
from app.config import DEFAULT_CFG


def synth(n=300, step=60, drift=0.0, vol=0.0006, seed=1, start=1.1):
    rng = np.random.default_rng(seed)
    close = start * np.exp(np.cumsum(rng.normal(drift, vol, n)))
    open_ = np.r_[close[0], close[:-1]]
    hi = np.maximum(open_, close) * (1 + np.abs(rng.normal(0, vol / 3, n)))
    lo = np.minimum(open_, close) * (1 - np.abs(rng.normal(0, vol / 3, n)))
    return pd.DataFrame({"time": np.arange(n) * step + 1_700_000_000, "open": open_, "high": hi, "low": lo, "close": close})


def frames(seed, drift=0.0003):
    return {tf: synth(250, step, drift, seed=seed + i) for i, (tf, step) in
            enumerate(zip(TF_ORDER, [86400, 14400, 3600, 900, 300]))}


def test_indicators_and_overlay():
    ov = overlay(synth(), "M15")
    assert ov["bias"] in ("bullish", "bearish", "neutral")
    assert len(ov["indicators"]["ema20"]) == 300
    import json; json.dumps(ov)  # must be JSON serialisable


def test_analyze_never_crashes_and_signals_are_consistent():
    valid = 0
    for seed in range(60):
        r = analyze_full(frames(seed, drift=0.0004 if seed % 2 else -0.0004))
        assert 0 <= r["best_score"] <= 100
        s = r["signal"]
        if s:
            valid += 1
            assert s["rr"] >= 1.5 or s["rr"] > 0
            if s["direction"] == "BUY":
                assert s["sl"] < s["entry"] < s["tp1"]
            else:
                assert s["sl"] > s["entry"] > s["tp1"]
    print("valid signals in 60 random markets:", valid)


def test_synthetic_symbols_are_recognized():
    for s in ("R_75", "1HZ75V", "BOOM1000", "BOOM500", "CRASH1000", "CRASH300N"):
        assert is_synthetic(s)
        assert synth_kind(s) in ("vol", "boom", "crash")
    assert not is_synthetic("frxEURUSD")
    assert synth_kind("frxEURUSD") is None
    assert is_synthetic("SOMEIDX", "synthetic_index")


def test_synthetic_rank_is_not_dropped_when_neutral():
    score, _ = quick_rank(synth(drift=0.0, vol=0.0002, seed=3), synthetic=True)
    assert score > 0


def test_synthetic_analysis_runs_for_boom_crash_and_vol():
    up = frames(7, drift=0.0008)
    for symbol, kind in (("BOOM1000", "boom"), ("CRASH1000", "crash"), ("R_75", "vol")):
        r = analyze_full(up, symbol)
        assert r["kind"] == kind
        assert 0 <= r["best_score"] <= 100
        s = r["signal"]
        if s:
            assert s["rr"] >= 1.5
            assert s["durations"]
            if s["direction"] == "BUY":
                assert s["sl"] < s["entry"] < s["tp1"]
            else:
                assert s["sl"] > s["entry"] > s["tp1"]


def test_synthetic_threshold_matches_forex_bar():
    cfg = {**DEFAULT_CFG, "threshold_forex": 72, "threshold_synth": 82}
    assert entry_threshold("R_75", cfg) == 72
    assert entry_threshold("BOOM1000", cfg) == 72
    assert entry_threshold("frxEURUSD", cfg) == 72


def test_risk_small_account():
    p, _ = plan_basket(10, 0, DEFAULT_CFG, 80)
    assert p["n"] == 1 and p["total"] <= 0.5 + 1e-9


def test_risk_never_exceeds_budget():
    for bal in [10, 25, 50, 100, 500, 1000, 10000]:
        for score in [72, 80, 90, 100]:
            p, _ = plan_basket(bal, 0, DEFAULT_CFG, score)
            if p:
                assert p["total"] <= bal * DEFAULT_CFG["risk_pct"] / 100 + 0.01
                assert p["stake"] >= DEFAULT_CFG["min_stake"]
                assert p["n"] <= DEFAULT_CFG["max_bulk"]


def test_risk_refuses_tiny_balance_and_full_exposure():
    assert plan_basket(2, 0, DEFAULT_CFG, 90)[0] is None
    assert plan_basket(100, 14.9, DEFAULT_CFG, 90)[0] is None
