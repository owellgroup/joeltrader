package com.joeltrader.service;

import com.joeltrader.domain.Trade;
import com.joeltrader.repo.TradeRepo;
import org.springframework.stereotype.Service;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;
import java.util.*;
import java.util.stream.Collectors;

@Service
public class PerformanceService {
    private final TradeRepo trades;

    public PerformanceService(TradeRepo trades) { this.trades = trades; }

    private static double p(Trade t) { return t.profit == null ? 0 : t.profit; }

    public Map<String, Object> compute(Long userId, int days) {
        return compute(trades.findByUserIdAndStatusNotAndClosedAtAfterOrderByClosedAtAsc(
                userId, "OPEN", Instant.now().minus(days, ChronoUnit.DAYS)));
    }

    public Map<String, Object> compute(List<Trade> list) {
        int n = list.size();
        double net = list.stream().mapToDouble(PerformanceService::p).sum();
        double gw = list.stream().mapToDouble(PerformanceService::p).filter(x -> x > 0).sum();
        double gl = -list.stream().mapToDouble(PerformanceService::p).filter(x -> x < 0).sum();
        long wins = list.stream().filter(t -> p(t) > 0).count();
        long losses = list.stream().filter(t -> p(t) < 0).count();
        double cum = 0, peak = 0, maxDd = 0;
        List<Map<String, Object>> curve = new ArrayList<>();
        for (Trade t : list) {
            cum += p(t);
            peak = Math.max(peak, cum);
            maxDd = Math.max(maxDd, peak - cum);
            curve.add(Map.of("t", t.closedAt.toString(), "equity", round(cum)));
        }
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("trades", n);
        m.put("wins", wins);
        m.put("losses", losses);
        m.put("netProfit", round(net));
        m.put("winRate", n == 0 ? 0 : round(100.0 * wins / n));
        Object pf = gl == 0 ? (Object) (gw > 0 ? null : (Object) 0.0) : (Object) round(gw / gl);
        m.put("profitFactor", pf);
        m.put("avgWin", wins == 0 ? 0 : round(gw / wins));
        m.put("avgLoss", losses == 0 ? 0 : round(-gl / losses));
        m.put("expectancy", n == 0 ? 0 : round(net / n));
        m.put("maxDrawdown", round(maxDd));
        m.put("best", round(list.stream().mapToDouble(PerformanceService::p).max().orElse(0)));
        m.put("worst", round(list.stream().mapToDouble(PerformanceService::p).min().orElse(0)));
        m.put("equityCurve", curve);
        m.put("bySymbol", group(list, t -> String.valueOf(t.symbol)));
        m.put("byDay", group(list, t -> t.closedAt.atZone(ZoneOffset.UTC).toLocalDate().toString()));
        m.put("byHour", group(list, t -> String.format("%02d", t.closedAt.atZone(ZoneOffset.UTC).getHour())));
        m.put("byKind", group(list, t -> String.valueOf(t.kind)));
        return m;
    }

    private List<Map<String, Object>> group(List<Trade> list, java.util.function.Function<Trade, String> key) {
        Map<String, List<Trade>> g = list.stream().collect(Collectors.groupingBy(key, TreeMap::new, Collectors.toList()));
        List<Map<String, Object>> out = new ArrayList<>();
        g.forEach((k, v) -> {
            long w = v.stream().filter(t -> p(t) > 0).count();
            out.add(Map.of("key", k, "trades", v.size(), "wins", w,
                    "net", round(v.stream().mapToDouble(PerformanceService::p).sum()),
                    "winRate", round(100.0 * w / v.size())));
        });
        return out;
    }

    static double round(double v) { return Math.round(v * 100.0) / 100.0; }
}
