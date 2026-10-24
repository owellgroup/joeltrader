package com.joeltrader.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.joeltrader.domain.BotSetting;
import com.joeltrader.domain.DerivAccount;
import com.joeltrader.repo.BotSettingRepo;
import com.joeltrader.repo.DerivAccountRepo;
import com.joeltrader.security.CryptoService;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClientResponseException;
import org.springframework.web.server.ResponseStatusException;
import java.util.*;

@Service
public class BotService {
    /** Server-side limits: whatever the app sends, risk settings can never exceed these. */
    static final Map<String, double[]> RANGES = new LinkedHashMap<>();
    static {
        RANGES.put("risk_pct", new double[]{0.5, 10});
        RANGES.put("max_exposure_pct", new double[]{1, 30});
        RANGES.put("max_single_stake_pct", new double[]{1, 20});
        RANGES.put("min_stake", new double[]{0.35, 50});
        RANGES.put("max_bulk", new double[]{1, 20});
        RANGES.put("tp_pct", new double[]{5, 200});
        RANGES.put("sl_pct", new double[]{10, 100});
        RANGES.put("daily_loss_pct", new double[]{1, 25});
        RANGES.put("max_drawdown_pct", new double[]{5, 50});
        RANGES.put("loss_streak_cooldown", new double[]{1, 10});
        RANGES.put("cooldown_minutes", new double[]{5, 1440});
        RANGES.put("threshold_forex", new double[]{60, 95});
        RANGES.put("threshold_synth", new double[]{60, 95});
        RANGES.put("scan_interval", new double[]{20, 600});
        RANGES.put("news_blackout_before", new double[]{5, 120});
        RANGES.put("news_blackout_after", new double[]{0, 60});
        RANGES.put("news_risk_pct", new double[]{0.5, 6});
    }
    static final Set<String> BOOLS = Set.of("include_synthetics", "news_gold");

    private final BotSettingRepo settings;
    private final DerivAccountRepo accounts;
    private final CryptoService crypto;
    private final EngineClient engine;
    private final ObjectMapper om = new ObjectMapper();

    public BotService(BotSettingRepo settings, DerivAccountRepo accounts, CryptoService crypto, EngineClient engine) {
        this.settings = settings; this.accounts = accounts; this.crypto = crypto; this.engine = engine;
    }

    public Map<String, Object> sanitize(Map<String, Object> in) {
        Map<String, Object> out = new LinkedHashMap<>();
        if (in == null) return out;
        in.forEach((k, v) -> {
            if (RANGES.containsKey(k) && v instanceof Number n) {
                double[] r = RANGES.get(k);
                double x = Math.max(r[0], Math.min(r[1], n.doubleValue()));
                out.put(k, k.equals("max_bulk") || k.contains("minutes") || k.equals("scan_interval") || k.startsWith("threshold")
                        || k.equals("loss_streak_cooldown") || k.startsWith("news_blackout") ? (Object) (int) x : (Object) x);
            } else if (BOOLS.contains(k) && v instanceof Boolean) out.put(k, v);
        });
        return out;
    }

    public Map<String, Object> config(BotSetting s) {
        try { return om.readValue(s.configJson == null ? "{}" : s.configJson, new TypeReference<>() {}); }
        catch (Exception e) { return new HashMap<>(); }
    }

    public BotSetting setting(Long userId) { return settings.findById(userId).orElseGet(() -> new BotSetting(userId)); }

    public void saveConfig(Long userId, Map<String, Object> cfg) {
        BotSetting s = setting(userId);
        Map<String, Object> merged = config(s);
        merged.putAll(sanitize(cfg));
        try { s.configJson = om.writeValueAsString(merged); } catch (Exception e) { throw new IllegalStateException(e); }
        settings.save(s);
        if (s.running) {
            try { engine.post("/bots/" + userId + "/config", merged); } catch (Exception ignored) { }
        }
    }

    public void start(Long userId, Long accountRefId, Map<String, Object> cfg, boolean allowReal) {
        DerivAccount a = accounts.findByIdAndUserId(accountRefId, userId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Account not found"));
        if ("REAL".equals(a.accountType) && !allowReal)
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "This is a REAL account. Test on a demo account first; to trade real money you must tick 'I allow real trading'.");
        BotSetting s = setting(userId);
        s.derivAccountId = a.id;
        s.running = true;
        settings.save(s);
        saveConfig(userId, cfg);
        BotSetting s2 = setting(userId);
        Map<String, Object> saved = config(s2);
        saved.put("allow_real_saved", allowReal);
        try { s2.configJson = om.writeValueAsString(saved); } catch (Exception e) { throw new IllegalStateException(e); }
        settings.save(s2);
        pushStart(s2, a, allowReal);
    }

    private void pushStart(BotSetting s, DerivAccount a, boolean allowReal) {
        Map<String, Object> c = config(s);
        c.put("allow_real", allowReal && "REAL".equals(a.accountType));
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("userId", s.userId);
        body.put("accountId", a.accountId);
        body.put("accountType", a.accountType);
        body.put("token", crypto.decrypt(a.tokenEnc));
        body.put("appId", a.appId);
        body.put("config", c);
        try {
            engine.post("/bots/start", body);
        } catch (RestClientResponseException e) {
            s.running = false; settings.save(s);
            throw new ResponseStatusException(HttpStatus.BAD_GATEWAY, "Engine refused to start the bot: " + e.getResponseBodyAsString());
        } catch (Exception e) {
            s.running = false; settings.save(s);
            throw new ResponseStatusException(HttpStatus.BAD_GATEWAY, "Trading engine is not reachable");
        }
    }

    /** Used by the reconciler after an engine restart: real accounts are NOT auto-resumed unless they were allowed. */
    public void resume(BotSetting s) {
        Optional<DerivAccount> a = s.derivAccountId == null ? Optional.empty() : accounts.findById(s.derivAccountId);
        if (a.isEmpty()) { s.running = false; settings.save(s); return; }
        boolean allowReal = Boolean.TRUE.equals(config(s).get("allow_real_saved"));
        if ("REAL".equals(a.get().accountType) && !allowReal) { s.running = false; settings.save(s); return; }
        pushStart(s, a.get(), allowReal);
    }

    public void stop(Long userId, boolean closeOpen) {
        BotSetting s = setting(userId);
        s.running = false;
        settings.save(s);
        try { engine.post("/bots/stop", Map.of("userId", userId, "closeOpen", closeOpen)); } catch (Exception ignored) { }
    }

    public JsonNode state(Long userId) {
        try { return engine.get("/bots/" + userId); }
        catch (Exception e) { return om.createObjectNode().put("running", false).put("phase", "engine offline"); }
    }
}
