package com.joeltrader.service;

import com.fasterxml.jackson.databind.JsonNode;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;

/** Talks to the Python engine on the private docker network. */
@Service
public class EngineClient {
    private final RestClient rc;

    public EngineClient(@Value("${app.engine-url}") String url, @Value("${app.internal-key}") String key) {
        SimpleClientHttpRequestFactory f = new SimpleClientHttpRequestFactory();
        f.setConnectTimeout(3000);
        f.setReadTimeout(90000);
        rc = RestClient.builder().baseUrl(url).requestFactory(f).defaultHeader("X-Internal-Key", key).build();
    }

    /** kv = key1, value1, key2, value2 ... */
    public JsonNode get(String path, String... kv) {
        return rc.get().uri(b -> {
            var ub = b.path(path);
            for (int i = 0; i + 1 < kv.length; i += 2) ub = ub.queryParam(kv[i], kv[i + 1]);
            return ub.build();
        }).retrieve().body(JsonNode.class);
    }

    public JsonNode post(String path, Object body) {
        return rc.post().uri(path).body(body).retrieve().body(JsonNode.class);
    }
}
