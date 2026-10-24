package com.joeltrader.service;

import com.fasterxml.jackson.databind.JsonNode;
import org.springframework.http.HttpStatus;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientResponseException;
import org.springframework.web.server.ResponseStatusException;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** Deriv REST API (https://developers.deriv.com/docs): list the accounts a Personal Access Token can see. */
@Service
public class DerivRest {
    private final RestClient rc;

    public DerivRest() {
        SimpleClientHttpRequestFactory f = new SimpleClientHttpRequestFactory();
        f.setConnectTimeout(5000);
        f.setReadTimeout(15000);
        rc = RestClient.builder().requestFactory(f).baseUrl("https://api.derivws.com").build();
    }

    public List<Map<String, Object>> accounts(String token, String appId) {
        try {
            JsonNode root = rc.get().uri("/trading/v1/options/accounts")
                    .headers(h -> {
                        h.setBearerAuth(token);
                        if (appId != null && !appId.isBlank()) h.set("Deriv-App-ID", appId);
                    }).retrieve().body(JsonNode.class);
            JsonNode arr = root != null && root.has("data") ? root.get("data") : root;
            List<Map<String, Object>> out = new ArrayList<>();
            if (arr != null && arr.isArray()) for (JsonNode a : arr) out.add(normalise(a));
            return out;
        } catch (RestClientResponseException e) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Deriv rejected the token (HTTP " + e.getStatusCode().value() + "). Check the token scope (trade) and App ID.");
        }
    }

    private static String first(JsonNode a, String... names) {
        for (String n : names) if (a.hasNonNull(n)) return a.get(n).asText();
        return null;
    }

    private static Map<String, Object> normalise(JsonNode a) {
        String id = first(a, "account_id", "accountId", "loginid", "id");
        String type = first(a, "account_type", "type");
        boolean demo = (type != null && (type.toLowerCase().contains("demo") || type.toLowerCase().contains("virtual")))
                || "1".equals(first(a, "is_virtual")) || "true".equals(first(a, "is_virtual"))
                || (id != null && (id.startsWith("VR") || id.startsWith("DOT9")));
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("accountId", id);
        m.put("accountType", demo ? "DEMO" : "REAL");
        m.put("balance", a.hasNonNull("balance") ? a.get("balance").asDouble() : null);
        m.put("currency", first(a, "currency"));
        m.put("raw", a);
        return m;
    }
}
