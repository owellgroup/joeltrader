package com.joeltrader.api;

import com.fasterxml.jackson.databind.JsonNode;
import com.joeltrader.domain.BotSetting;
import com.joeltrader.security.AuthUser;
import com.joeltrader.service.BotService;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import java.util.LinkedHashMap;
import java.util.Map;

@RestController
@RequestMapping("/api/bot")
public class BotController {
    public record StartReq(Long accountId, Map<String, Object> config, Boolean allowReal) {}
    public record StopReq(Boolean closeOpen) {}

    private final BotService bots;

    public BotController(BotService bots) { this.bots = bots; }

    @GetMapping
    public Map<String, Object> get(@AuthenticationPrincipal AuthUser me) {
        BotSetting s = bots.setting(me.id());
        JsonNode state = bots.state(me.id());
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("running", s.running);
        m.put("accountId", s.derivAccountId);
        m.put("config", bots.config(s));
        m.put("lastBalance", s.lastBalance);
        m.put("state", state);
        return m;
    }

    @PostMapping("/start")
    public Map<String, Object> start(@AuthenticationPrincipal AuthUser me, @RequestBody StartReq r) {
        if (r.accountId() == null) throw new IllegalArgumentException("accountId is required");
        bots.start(me.id(), r.accountId(), r.config(), Boolean.TRUE.equals(r.allowReal()));
        return Map.of("started", true);
    }

    @PostMapping("/stop")
    public Map<String, Object> stop(@AuthenticationPrincipal AuthUser me, @RequestBody(required = false) StopReq r) {
        bots.stop(me.id(), r != null && Boolean.TRUE.equals(r.closeOpen()));
        return Map.of("stopped", true);
    }

    @PutMapping("/config")
    public Map<String, Object> config(@AuthenticationPrincipal AuthUser me, @RequestBody Map<String, Object> cfg) {
        bots.saveConfig(me.id(), cfg);
        return bots.config(bots.setting(me.id()));
    }
}
