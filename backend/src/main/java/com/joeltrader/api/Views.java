package com.joeltrader.api;

import com.joeltrader.domain.User;
import java.util.LinkedHashMap;
import java.util.Map;

final class Views {
    private Views() {}

    static Map<String, Object> user(User u) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", u.id); m.put("email", u.email); m.put("name", u.name); m.put("role", u.role);
        m.put("enabled", u.enabled); m.put("mustChangePassword", u.mustChangePassword); m.put("createdAt", u.createdAt);
        return m;
    }
}
