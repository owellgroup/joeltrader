package com.joeltrader.api;

import com.fasterxml.jackson.databind.JsonNode;
import com.joeltrader.service.EventService;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Map;

/** Engine -> backend only (shared secret). Not reachable from the internet if you do not publish it through your proxy. */
@RestController
@RequestMapping("/internal")
public class InternalController {
    private final EventService events;
    private final String key;

    public InternalController(EventService events, @Value("${app.internal-key}") String key) { this.events = events; this.key = key; }

    @PostMapping("/events")
    public Map<String, Object> events(@RequestHeader(value = "X-Internal-Key", defaultValue = "") String k, @RequestBody JsonNode body) {
        if (!MessageDigest.isEqual(k.getBytes(StandardCharsets.UTF_8), key.getBytes(StandardCharsets.UTF_8)))
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED);
        events.handle(body.get("userId").asLong(), body.get("type").asText(), body.path("data"));
        return Map.of("ok", true);
    }
}
