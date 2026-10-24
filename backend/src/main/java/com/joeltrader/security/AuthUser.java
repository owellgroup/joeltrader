package com.joeltrader.security;

public record AuthUser(Long id, String email, String role) {
    public boolean isSuper() { return "SUPER_ADMIN".equals(role); }
}
