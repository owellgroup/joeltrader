package com.joeltrader.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.joeltrader.domain.BotSetting;
import com.joeltrader.domain.SignalRec;
import com.joeltrader.domain.Trade;
import com.joeltrader.domain.User;
import com.joeltrader.repo.BotSettingRepo;
import com.joeltrader.repo.SignalRepo;
import com.joeltrader.repo.TradeRepo;
import com.joeltrader.repo.UserRepo;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

/** Persists what the trading engine reports and sends the matching emails. */
@Service
public class EventService {
    private final TradeRepo trades;
    private final SignalRepo signals;
    private final BotSettingRepo settings;
    private final UserRepo users;
    private final MailService mail;

    public EventService(TradeRepo trades, SignalRepo signals, BotSettingRepo settings, UserRepo users, MailService mail) {
        this.trades = trades; this.signals = signals; this.settings = settings; this.users = users; this.mail = mail;
    }

    private static Double d(JsonNode n, String f) { return n.hasNonNull(f) ? n.get(f).asDouble() : null; }
    private static String s(JsonNode n, String f) { return n.hasNonNull(f) ? n.get(f).asText() : null; }

    @Transactional
    public void handle(Long userId, String type, JsonNode d) {
        User u = users.findById(userId).orElse(null);
        if (u == null) return;
        switch (type) {
            case "trade_open" -> {
                if (trades.findByTradeRef(s(d, "tradeRef")).isPresent()) return;
                Trade t = new Trade();
                t.userId = userId; t.tradeRef = s(d, "tradeRef"); t.basketId = s(d, "basketId"); t.accountId = s(d, "accountId");
                t.symbol = s(d, "symbol"); t.direction = s(d, "direction"); t.kind = s(d, "kind"); t.stake = d(d, "stake");
                t.score = d.hasNonNull("score") ? d.get("score").asInt() : null;
                t.reason = s(d, "reason"); t.durationMin = d.hasNonNull("durationMin") ? d.get("durationMin").asInt() : null;
                t.entry = d(d, "entry"); t.sl = d(d, "sl"); t.tp = d(d, "tp"); t.openedAt = Instant.now();
                trades.save(t);
            }
            case "trade_close" -> {
                Trade t = trades.findByTradeRef(s(d, "tradeRef")).orElseGet(() -> {
                    Trade n = new Trade(); n.userId = userId; n.tradeRef = s(d, "tradeRef"); n.kind = "ADOPTED"; n.openedAt = Instant.now(); return n;
                });
                if (!"OPEN".equals(t.status) && t.closedAt != null) return;
                t.profit = d(d, "profit"); t.sellPrice = d(d, "sellPrice"); t.closedAt = Instant.now();
                t.status = t.profit != null && t.profit > 0 ? "WON" : "LOST";
                trades.save(t);
            }
            case "basket_close" -> {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("basketId", s(d, "basketId")); m.put("symbol", s(d, "symbol"));
                m.put("pnl", d(d, "pnl")); m.put("stake", d(d, "stake"));
                mail.basket(u.email, m);
            }
            case "signal" -> {
                SignalRec r = new SignalRec();
                r.userId = userId; r.symbol = s(d, "symbol"); r.direction = s(d, "direction"); r.entry = d(d, "entry"); r.sl = d(d, "sl");
                r.tp1 = d(d, "tp1"); r.tp2 = d(d, "tp2"); r.rr = d(d, "rr"); r.score = d.hasNonNull("score") ? d.get("score").asInt() : null;
                r.tf = s(d, "tf"); r.source = "WATCH";
                StringBuilder sb = new StringBuilder();
                if (d.has("reasons")) d.get("reasons").forEach(x -> sb.append(x.asText()).append("\n"));
                r.reasons = sb.toString().trim(); r.emailed = true;
                signals.save(r);
                mail.signal(u.email, r);
            }
            case "balance" -> {
                BotSetting b = settings.findById(userId).orElseGet(() -> new BotSetting(userId));
                b.lastBalance = d(d, "balance"); b.dayPnl = d(d, "dayPnl"); b.lastBalanceAt = Instant.now();
                settings.save(b);
            }
            case "bot_state" -> {
                BotSetting b = settings.findById(userId).orElseGet(() -> new BotSetting(userId));
                if (d.has("running") && !d.get("running").asBoolean()) {
                    String reason = s(d, "reason");
                    if (reason != null && reason.startsWith("error")) {
                        b.running = false; settings.save(b);
                        mail.alert(u.email, "Bot stopped", "The trading bot stopped: " + reason);
                    }
                }
            }
            case "halt" -> {
                mail.alert(u.email, "Trading halted", "Reason: " + s(d, "reason") + ". Balance: " + d(d, "balance")
                        + (d.has("dayPnl") ? ", day P/L: " + d(d, "dayPnl") : ""));
                if ("max drawdown kill switch".equals(s(d, "reason"))) {
                    BotSetting b = settings.findById(userId).orElseGet(() -> new BotSetting(userId));
                    b.running = false; settings.save(b);
                }
            }
            default -> { }
        }
    }
}
