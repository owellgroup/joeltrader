package com.joeltrader.security;

import com.joeltrader.domain.User;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Date;

@Service
public class JwtService {
    private final SecretKey key;
    private final long days;

    public JwtService(@Value("${app.jwt-secret}") String secret, @Value("${app.jwt-days}") long days) {
        this.key = Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));
        this.days = days;
    }

    public String create(User u) {
        Instant now = Instant.now();
        return Jwts.builder().subject(String.valueOf(u.id)).claim("email", u.email).claim("role", u.role)
                .issuedAt(Date.from(now)).expiration(Date.from(now.plus(days, ChronoUnit.DAYS))).signWith(key).compact();
    }

    public Long parse(String token) {
        return Long.valueOf(Jwts.parser().verifyWith(key).build().parseSignedClaims(token).getPayload().getSubject());
    }
}
