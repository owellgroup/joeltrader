package com.joeltrader.api;

import com.joeltrader.domain.Trade;
import com.joeltrader.repo.TradeRepo;
import com.joeltrader.security.AuthUser;
import com.joeltrader.service.PerformanceService;
import com.joeltrader.service.Schedulers;
import com.joeltrader.repo.UserRepo;
import org.springframework.data.domain.PageRequest;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api")
public class TradeController {
    private final TradeRepo trades;
    private final PerformanceService perf;
    private final Schedulers schedulers;
    private final UserRepo users;

    public TradeController(TradeRepo trades, PerformanceService perf, Schedulers schedulers, UserRepo users) {
        this.trades = trades; this.perf = perf; this.schedulers = schedulers; this.users = users;
    }

    @GetMapping("/trades")
    public Map<String, Object> list(@AuthenticationPrincipal AuthUser me, @RequestParam(defaultValue = "0") int page,
                                    @RequestParam(defaultValue = "50") int size) {
        var p = trades.findByUserIdOrderByOpenedAtDesc(me.id(), PageRequest.of(page, Math.min(size, 200)));
        return Map.of("items", p.getContent(), "total", p.getTotalElements(), "page", page);
    }

    @GetMapping("/trades/open")
    public List<Trade> open(@AuthenticationPrincipal AuthUser me) {
        return trades.findByUserIdAndStatusOrderByOpenedAtDesc(me.id(), "OPEN");
    }

    @GetMapping("/performance")
    public Map<String, Object> performance(@AuthenticationPrincipal AuthUser me, @RequestParam(defaultValue = "30") int days) {
        return perf.compute(me.id(), Math.min(Math.max(days, 1), 365));
    }

    @PostMapping("/reports/send-now")
    public Map<String, Object> sendNow(@AuthenticationPrincipal AuthUser me, @RequestParam(defaultValue = "1") int days) {
        schedulers.sendReport(users.findById(me.id()).orElseThrow(), Math.min(Math.max(days, 1), 90));
        return Map.of("sent", true);
    }
}
