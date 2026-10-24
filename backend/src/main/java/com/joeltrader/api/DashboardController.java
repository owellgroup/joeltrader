package com.joeltrader.api;

import com.fasterxml.jackson.databind.JsonNode;
import com.joeltrader.domain.BotSetting;
import com.joeltrader.repo.SignalRepo;
import com.joeltrader.repo.TradeRepo;
import com.joeltrader.security.AuthUser;
import com.joeltrader.service.BotService;
import com.joeltrader.service.EngineClient;
import com.joeltrader.service.PerformanceService;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.LinkedHashMap;
import java.util.Map;

@RestController
@RequestMapping("/api/dashboard")
public class DashboardController {
    private final BotService bots;
    private final PerformanceService perf;
    private final TradeRepo trades;
    private final SignalRepo signals;
    private final EngineClient engine;

    public DashboardController(BotService bots, PerformanceService perf, TradeRepo trades, SignalRepo signals, EngineClient engine) {
        this.bots = bots; this.perf = perf; this.trades = trades; this.signals = signals; this.engine = engine;
    }

    @GetMapping
    public Map<String, Object> get(@AuthenticationPrincipal AuthUser me) {
        BotSetting s = bots.setting(me.id());
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("bot", bots.state(me.id()));
        m.put("botRunning", s.running);
        m.put("lastBalance", s.lastBalance);
        m.put("performance30d", perf.compute(me.id(), 30));
        m.put("today", perf.compute(trades.findByUserIdAndStatusNotAndClosedAtAfterOrderByClosedAtAsc(
                me.id(), "OPEN", Instant.now().truncatedTo(ChronoUnit.DAYS))));
        m.put("openTrades", trades.findByUserIdAndStatusOrderByOpenedAtDesc(me.id(), "OPEN"));
        m.put("recentSignals", signals.findTop50ByUserIdOrderByCreatedAtDesc(me.id()).stream().limit(5).toList());
        try { m.put("quotes", engine.get("/quotes")); } catch (Exception e) { m.put("quotes", java.util.List.of()); }
        return m;
    }
}
