import os

INTERNAL_KEY = os.getenv("INTERNAL_KEY", "change-me")
BACKEND_URL = os.getenv("BACKEND_URL", "http://backend:8181")
DERIV_REST = os.getenv("DERIV_REST", "https://api.derivws.com")
DERIV_WS_PUBLIC = os.getenv("DERIV_WS_PUBLIC", "wss://api.derivws.com/trading/v1/options/ws/public")
# New Deriv options API names this field underlying_symbol. "symbol" is rejected
# with InputValidationFailed: symbol,underlying_symbol.
DERIV_SYMBOL_KEY = os.getenv("DERIV_SYMBOL_KEY", "underlying_symbol")
CALENDAR_URL = os.getenv("CALENDAR_URL", "https://nfs.faireconomy.media/ff_calendar_thisweek.json")

GRAN = {"M1": 60, "M5": 300, "M15": 900, "M30": 1800, "H1": 3600, "H4": 14400, "D1": 86400}
GOLD = "frxXAUUSD"

DEFAULT_CFG = {
    "risk_pct": 5.0,              # max total stake of one basket, % of balance
    "max_exposure_pct": 15.0,     # max total open stake, % of balance
    "max_single_stake_pct": 10.0, # one contract may never exceed this % of balance
    "min_stake": 0.35,
    "max_bulk": 10,               # max contracts per basket
    "tp_pct": 25.0,               # close basket when profit >= % of basket stake
    "sl_pct": 50.0,               # close basket when loss >= % of basket stake
    "daily_loss_pct": 10.0,       # stop opening trades for the day after this realised loss
    "max_drawdown_pct": 25.0,     # kill switch: stop the bot if balance falls this far from peak
    "loss_streak_cooldown": 3,
    "cooldown_minutes": 60,
    "threshold_forex": 72,
    "threshold_synth": 72,
    "include_synthetics": True,
    "scan_interval": 45,
    "news_blackout_before": 30,
    "news_blackout_after": 15,
    "news_gold": False,           # gold NFP news trader
    "news_risk_pct": 3.0,
    "allow_real": False,          # real accounts need an explicit opt-in
}
