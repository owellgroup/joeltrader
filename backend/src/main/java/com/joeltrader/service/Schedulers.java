package com.joeltrader.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.joeltrader.domain.BotSetting;
import com.joeltrader.domain.Trade;
import com.joeltrader.domain.User;
import com.joeltrader.domain.WatchSymbol;
import com.joeltrader.repo.BotSettingRepo;
import com.joeltrader.repo.TradeRepo;
import com.joeltrader.repo.UserRepo;
import com.joeltrader.repo.WatchRepo;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.*;
import java.util.stream.Collectors;

@Component
public class Schedulers {
    private static final Logger log = LoggerFactory.getLogger(Schedulers.class);
    private final EngineClient engine;
    private final BotSettingRepo settings;
    private final BotService bots;
    private final WatchRepo watch;
    private final UserRepo users;
    private final TradeRepo trades;
    private final PerformanceService perf;
    private final MailService mail;

    public Schedulers(EngineClient engine, BotSettingRepo settings, BotService bots, WatchRepo watch, UserRepo users,
                      TradeRepo trades, PerformanceService perf, MailService mail) {
        this.engine = engine; this.settings = settings; this.bots = bots; this.watch = watch; this.users = users;
        this.trades = trades; this.perf = perf; this.mail = mail;
    }

    /** Keeps the 24/7 promise: if the engine restarted, bots flagged as running are started again. */
    @Scheduled(fixedDelay = 30000, initialDelay = 20000)
    public void reconcile() {
        try {
            JsonNode running = engine.get("/bots");
            Set<Long> live = new HashSet<>();
            running.forEach(n -> live.add(n.asLong()));
            for (BotSetting s : settings.findByRunningTrue()) {
                if (!live.contains(s.userId)) {
                    try { bots.resume(s); log.info("resumed bot for user {}", s.userId); }
                    catch (Exception e) { log.warn("resume failed for {}: {}", s.userId, e.getMessage()); }
                }
            }
            Map<Long, List<String>> w = watch.findAll().stream().filter(x -> x.signals)
                    .collect(Collectors.groupingBy(x -> x.userId, Collectors.mapping(x -> x.symbol, Collectors.toList())));
            w.forEach((uid, syms) -> engine.post("/watch", Map.of("userId", uid, "symbols", syms)));
        } catch (Exception e) {
            log.debug("engine not reachable: {}", e.getMessage());
        }
    }

    @Scheduled(cron = "${app.report-cron}")
    public void dailyReports() {
        for (User u : users.findByEnabledTrue()) {
            try { sendReport(u, 1); } catch (Exception e) { log.warn("report for {} failed: {}", u.email, e.getMessage()); }
        }
    }

    @SuppressWarnings("unchecked")
    public void sendReport(User u, int days) {
        Instant since = Instant.now().minus(days, ChronoUnit.DAYS);
        List<Trade> closed = trades.findByUserIdAndStatusNotAndClosedAtAfterOrderByClosedAtAsc(u.id, "OPEN", since);
        Map<String, Object> p = perf.compute(closed);
        StringBuilder sb = new StringBuilder();
        sb.append("<table>")
                .append(MailService.row("Net profit / loss", MailService.money(((Number) p.get("netProfit")).doubleValue())))
                .append(MailService.row("Trades", String.valueOf(p.get("trades"))))
                .append(MailService.row("Win rate", p.get("winRate") + "%"))
                .append(MailService.row("Profit factor", String.valueOf(p.get("profitFactor"))))
                .append(MailService.row("Best / worst trade", p.get("best") + " / " + p.get("worst")))
                .append(MailService.row("Max drawdown", String.valueOf(p.get("maxDrawdown"))));
        BotSetting bs = settings.findById(u.id).orElse(null);
        if (bs != null && bs.lastBalance != null) sb.append(MailService.row("Last known balance", String.valueOf(bs.lastBalance)));
        sb.append("</table><h3 style='color:#fff'>By symbol</h3><table style='width:100%;border-collapse:collapse'>");
        ((List<Map<String, Object>>) p.get("bySymbol")).forEach(r -> sb.append("<tr><td style='padding:4px 0'>")
                .append(MailService.esc(String.valueOf(r.get("key")))).append("</td><td>").append(r.get("trades")).append(" trades</td><td>")
                .append(r.get("winRate")).append("%</td><td style='text-align:right'>").append(MailService.money(((Number) r.get("net")).doubleValue())).append("</td></tr>"));
        sb.append("</table>");
        if (closed.isEmpty()) sb.append("<p>No trades were closed in this period.</p>");
        mail.send(u.email, "Daily trading report", MailService.wrap(days == 1 ? "Your daily report" : "Report: last " + days + " days", sb.toString()));
    }
}
