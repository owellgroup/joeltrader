package com.joeltrader.api;

import com.joeltrader.domain.User;
import com.joeltrader.repo.UserRepo;
import com.joeltrader.security.AuthUser;
import com.joeltrader.security.JwtService;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;
import java.util.Map;

@RestController
@RequestMapping("/api/auth")
public class AuthController {
    public record LoginReq(String email, String password) {}
    public record PasswordReq(String currentPassword, String newPassword) {}

    private final UserRepo users;
    private final PasswordEncoder enc;
    private final JwtService jwt;

    public AuthController(UserRepo users, PasswordEncoder enc, JwtService jwt) { this.users = users; this.enc = enc; this.jwt = jwt; }

    @PostMapping("/login")
    public Map<String, Object> login(@RequestBody LoginReq r) {
        User u = users.findByEmailIgnoreCase(r.email() == null ? "" : r.email().trim()).orElse(null);
        if (u == null || !u.enabled || r.password() == null || !enc.matches(r.password(), u.passwordHash))
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Invalid email or password");
        return Map.of("token", jwt.create(u), "user", Views.user(u));
    }

    @GetMapping("/me")
    public Map<String, Object> me(@AuthenticationPrincipal AuthUser me) {
        return Views.user(users.findById(me.id()).orElseThrow());
    }

    /** Sliding session: the app calls this on start so the user stays logged in. */
    @PostMapping("/refresh")
    public Map<String, Object> refresh(@AuthenticationPrincipal AuthUser me) {
        User u = users.findById(me.id()).orElseThrow();
        return Map.of("token", jwt.create(u), "user", Views.user(u));
    }

    @PostMapping("/change-password")
    public Map<String, Object> change(@AuthenticationPrincipal AuthUser me, @RequestBody PasswordReq r) {
        User u = users.findById(me.id()).orElseThrow();
        if (!enc.matches(r.currentPassword(), u.passwordHash)) throw new IllegalArgumentException("Current password is wrong");
        if (r.newPassword() == null || r.newPassword().length() < 8) throw new IllegalArgumentException("New password must be at least 8 characters");
        u.passwordHash = enc.encode(r.newPassword());
        u.mustChangePassword = false;
        users.save(u);
        return Map.of("ok", true);
    }
}
