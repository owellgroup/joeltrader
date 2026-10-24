package com.joeltrader.api;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.joeltrader.domain.SignalRec;
import com.joeltrader.domain.WatchSymbol;
import com.joeltrader.repo.SignalRepo;
import com.joeltrader.repo.UserRepo;
import com.joeltrader.repo.WatchRepo;
import com.joeltrader.security.AuthUser;
import com.joeltrader.service.EngineClient;
import com.joeltrader.service.MailService;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.Map;

/** Market data, charts, analysis and signals. Reads are proxied to the engine; signals are stored per user. */
@RestController
@RequestMapping("/api")
public class MarketController {
    public record WatchReq(Boolean favorite, Boolean signals) {}

    private final EngineClient engine;
    private final SignalRepo signals;
    private final WatchRepo watch;
    private final UserRepo users;
    private final MailService mail;

    public MarketController(EngineClient engine, SignalRepo signals, WatchRepo watch, UserRepo users, MailService mail) {
        this.engine = engine; this.signals = signals; this.watch = watch; this.users = users; this.mail = mail;
    }

    @GetMapping("/market/symbols") public JsonNode symbols() { return engine.get("/symbols"); }

    @GetMapping("/market/quotes")
    public JsonNode quotes(@RequestParam(defaultValue = "") String extra) { return engine.get("/quotes", "extra", extra); }

    @GetMapping("/market/calendar") public JsonNode calendar() { return engine.get("/calendar"); }

    @GetMapping("/market/candles")
    public JsonNode candles(@RequestParam String symbol, @RequestParam(defaultValue = "M15") String tf,
                            @RequestParam(defaultValue = "300") String count) {
        return engine.get("/candles", "symbol", symbol, "tf", tf, "count", count);
    }

    /** auto=false: candles + manual-analysis overlays. auto=true: full top-down analysis (D1 to M5) and a stored signal. */
    @GetMapping("/market/analyze")
    public JsonNode analyze(@AuthenticationPrincipal AuthUser me, @RequestParam String symbol, @RequestParam(defaultValue = "M15") String tf,
                            @RequestParam(defaultValue = "false") boolean auto, @RequestParam(defaultValue = "true") boolean email) {
        JsonNode r = engine.get("/analyze", "symbol", symbol, "tf", tf, "auto", String.valueOf(auto));
        if (auto && r.path("analysis").path("signal").isObject()) {
            JsonNode s = r.get("analysis").get("signal");
            SignalRec rec = new SignalRec();
            rec.userId = me.id(); rec.symbol = symbol; rec.source = "MANUAL"; rec.tf = "M5";
            rec.direction = s.path("direction").asText(); rec.entry = s.path("entry").asDouble(); rec.sl = s.path("sl").asDouble();
            rec.tp1 = s.path("tp1").asDouble(); rec.tp2 = s.path("tp2").asDouble(); rec.rr = s.path("rr").asDouble();
            rec.score = s.path("score").asInt();
            StringBuilder sb = new StringBuilder();
            s.path("reasons").forEach(x -> sb.append(x.asText()).append("\n"));
            rec.reasons = sb.toString().trim();
            rec.emailed = email;
            signals.save(rec);
            if (email) mail.signal(users.findById(me.id()).orElseThrow().email, rec);
            ((ObjectNode) r).put("signalId", rec.id).put("emailed", email);
        }
        return r;
    }

    @GetMapping("/signals")
    public List<SignalRec> signals(@AuthenticationPrincipal AuthUser me) { return signals.findTop50ByUserIdOrderByCreatedAtDesc(me.id()); }

    // ----- watchlist / favourites -----
    @GetMapping("/watchlist")
    public List<WatchSymbol> watchlist(@AuthenticationPrincipal AuthUser me) { return watch.findByUserIdOrderBySymbolAsc(me.id()); }

    @PutMapping("/watchlist/{symbol}")
    public WatchSymbol put(@AuthenticationPrincipal AuthUser me, @PathVariable String symbol, @RequestBody(required = false) WatchReq r) {
        WatchSymbol w = watch.findByUserIdAndSymbol(me.id(), symbol).orElseGet(() -> {
            WatchSymbol n = new WatchSymbol(); n.userId = me.id(); n.symbol = symbol; return n;
        });
        if (r != null && r.favorite() != null) w.favorite = r.favorite();
        if (r != null && r.signals() != null) w.signals = r.signals();
        return watch.save(w);
    }

    @DeleteMapping("/watchlist/{symbol}")
    @Transactional
    public Map<String, Object> remove(@AuthenticationPrincipal AuthUser me, @PathVariable String symbol) {
        watch.findByUserIdAndSymbol(me.id(), symbol).ifPresent(watch::delete);
        return Map.of("removed", symbol);
    }
}
