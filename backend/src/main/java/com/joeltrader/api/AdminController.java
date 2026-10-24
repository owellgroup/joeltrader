package com.joeltrader.api;

import com.joeltrader.domain.User;
import com.joeltrader.repo.*;
import com.joeltrader.security.AuthUser;
import com.joeltrader.service.BotService;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;
import java.util.List;
import java.util.Map;

/** Admins cannot sign up. An existing admin creates the others; only the super admin can disable or delete. */
@RestController
@RequestMapping("/api/admins")
public class AdminController {
    public record CreateReq(String email, String name, String password) {}
    public record EnabledReq(boolean enabled) {}

    private final UserRepo users;
    private final PasswordEncoder enc;
    private final DerivAccountRepo accounts;
    private final TradeRepo trades;
    private final SignalRepo signals;
    private final WatchRepo watch;
    private final BotSettingRepo settings;
    private final BotService bots;

    public AdminController(UserRepo users, PasswordEncoder enc, DerivAccountRepo accounts, TradeRepo trades, SignalRepo signals,
                           WatchRepo watch, BotSettingRepo settings, BotService bots) {
        this.users = users; this.enc = enc; this.accounts = accounts; this.trades = trades; this.signals = signals;
        this.watch = watch; this.settings = settings; this.bots = bots;
    }

    /** Lists admins (name/email/status only - never their trading data). */
    @GetMapping
    public List<Map<String, Object>> list() { return users.findAll().stream().map(Views::user).toList(); }

    @PostMapping
    public Map<String, Object> create(@RequestBody CreateReq r) {
        if (r.email() == null || !r.email().contains("@")) throw new IllegalArgumentException("Valid email required");
        if (r.password() == null || r.password().length() < 8) throw new IllegalArgumentException("Password must be at least 8 characters");
        if (users.findByEmailIgnoreCase(r.email().trim()).isPresent()) throw new ResponseStatusException(HttpStatus.CONFLICT, "Email already exists");
        User u = new User();
        u.email = r.email().trim().toLowerCase();
        u.name = r.name() == null || r.name().isBlank() ? u.email : r.name().trim();
        u.passwordHash = enc.encode(r.password());
        u.role = "ADMIN";
        u.mustChangePassword = true;
        return Views.user(users.save(u));
    }

    @PatchMapping("/{id}/enabled")
    public Map<String, Object> enabled(@AuthenticationPrincipal AuthUser me, @PathVariable Long id, @RequestBody EnabledReq r) {
        requireSuper(me);
        User u = users.findById(id).orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND));
        if ("SUPER_ADMIN".equals(u.role)) throw new IllegalArgumentException("The super admin cannot be disabled");
        u.enabled = r.enabled();
        if (!u.enabled) bots.stop(u.id, false);
        return Views.user(users.save(u));
    }

    @DeleteMapping("/{id}")
    @Transactional
    public Map<String, Object> delete(@AuthenticationPrincipal AuthUser me, @PathVariable Long id) {
        requireSuper(me);
        User u = users.findById(id).orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND));
        if ("SUPER_ADMIN".equals(u.role)) throw new IllegalArgumentException("The super admin cannot be deleted");
        bots.stop(id, true);
        trades.deleteByUserId(id); signals.deleteByUserId(id); watch.deleteByUserId(id);
        accounts.deleteByUserId(id); settings.deleteById(id);
        users.delete(u);
        return Map.of("deleted", id);
    }

    private static void requireSuper(AuthUser me) {
        if (!me.isSuper()) throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Only the super admin can do this");
    }
}
