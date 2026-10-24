"""Position sizing / account protection. All limits come from the bot config."""
import math


def plan_basket(balance, open_stake, cfg, score, kind="AUTO"):
    """Return (plan, reason). plan = {n, stake, total} or None when trading would be unsafe.

    On Deriv options the worst case per contract is the stake, so the worst case
    for a basket is the total stake - that is what the risk budget caps.
    """
    risk_pct = cfg["news_risk_pct"] if kind == "NEWS" else cfg["risk_pct"]
    min_stake = float(cfg["min_stake"])
    if balance <= 0:
        return None, "no balance"
    if min_stake > balance * cfg["max_single_stake_pct"] / 100:
        return None, f"balance {balance:.2f} too small: minimum stake {min_stake} exceeds {cfg['max_single_stake_pct']}% of it"
    room = balance * cfg["max_exposure_pct"] / 100 - open_stake
    budget = min(balance * risk_pct / 100, room)
    if budget < min_stake:
        return None, f"risk budget {budget:.2f} below minimum stake {min_stake}"
    n = max(1, min(int(cfg["max_bulk"]), math.floor(budget / min_stake + 1e-9)))
    factor = min(1.0, max(0.3, (score - 60) / 40))
    n = max(1, math.floor(n * factor))
    stake = math.floor(budget / n * 100) / 100
    stake = min(stake, math.floor(balance * cfg["max_single_stake_pct"]) / 100)
    if stake < min_stake:
        stake, n = min_stake, max(1, math.floor(budget / min_stake + 1e-9))
    return {"n": int(n), "stake": round(stake, 2), "total": round(n * stake, 2)}, "ok"
