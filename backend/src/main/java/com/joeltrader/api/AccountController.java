package com.joeltrader.api;

import com.joeltrader.domain.BotSetting;
import com.joeltrader.domain.DerivAccount;
import com.joeltrader.repo.BotSettingRepo;
import com.joeltrader.repo.DerivAccountRepo;
import com.joeltrader.security.AuthUser;
import com.joeltrader.security.CryptoService;
import com.joeltrader.service.DerivRest;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;
import java.util.*;

/** A user's own Deriv accounts. Every query is scoped by the logged-in user id. */
@RestController
@RequestMapping("/api/accounts")
public class AccountController {
    public record Discover(String token, String appId) {}
    public record Save(String label, String token, String appId, String accountId) {}
    public record Update(String label, String token, String appId) {}

    private final DerivAccountRepo repo;
    private final BotSettingRepo settings;
    private final CryptoService crypto;
    private final DerivRest deriv;

    public AccountController(DerivAccountRepo repo, BotSettingRepo settings, CryptoService crypto, DerivRest deriv) {
        this.repo = repo; this.settings = settings; this.crypto = crypto; this.deriv = deriv;
    }

    private static Map<String, Object> view(DerivAccount a) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", a.id); m.put("label", a.label); m.put("accountId", a.accountId); m.put("accountType", a.accountType);
        m.put("appId", a.appId); m.put("currency", a.currency); m.put("createdAt", a.createdAt);
        return m;
    }

    @GetMapping
    public List<Map<String, Object>> list(@AuthenticationPrincipal AuthUser me) {
        return repo.findByUserIdOrderByIdAsc(me.id()).stream().map(AccountController::view).toList();
    }

    /** Step 1: paste a Deriv Personal Access Token and see which accounts (demo / real, with balances) it can reach. */
    @PostMapping("/discover")
    public List<Map<String, Object>> discover(@RequestBody Discover r) {
        if (r.token() == null || r.token().isBlank()) throw new IllegalArgumentException("Token required");
        return deriv.accounts(r.token().trim(), r.appId());
    }

    /** Step 2: link the chosen account. */
    @PostMapping
    public Map<String, Object> save(@AuthenticationPrincipal AuthUser me, @RequestBody Save r) {
        if (r.token() == null || r.accountId() == null) throw new IllegalArgumentException("token and accountId are required");
        Map<String, Object> found = deriv.accounts(r.token().trim(), r.appId()).stream()
                .filter(a -> r.accountId().equals(a.get("accountId"))).findFirst()
                .orElseThrow(() -> new IllegalArgumentException("That token cannot access account " + r.accountId()));
        DerivAccount a = new DerivAccount();
        a.userId = me.id();
        a.label = r.label() == null || r.label().isBlank() ? r.accountId() : r.label().trim();
        a.accountId = r.accountId();
        a.accountType = String.valueOf(found.get("accountType"));
        a.currency = (String) found.get("currency");
        a.appId = r.appId();
        a.tokenEnc = crypto.encrypt(r.token().trim());
        return view(repo.save(a));
    }

    @PutMapping("/{id}")
    public Map<String, Object> update(@AuthenticationPrincipal AuthUser me, @PathVariable Long id, @RequestBody Update r) {
        DerivAccount a = own(me, id);
        if (r.label() != null && !r.label().isBlank()) a.label = r.label().trim();
        if (r.appId() != null) a.appId = r.appId();
        if (r.token() != null && !r.token().isBlank()) a.tokenEnc = crypto.encrypt(r.token().trim());
        return view(repo.save(a));
    }

    @DeleteMapping("/{id}")
    public Map<String, Object> delete(@AuthenticationPrincipal AuthUser me, @PathVariable Long id) {
        DerivAccount a = own(me, id);
        BotSetting s = settings.findById(me.id()).orElse(null);
        if (s != null && s.running && id.equals(s.derivAccountId))
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Stop the bot before deleting the account it trades on");
        repo.delete(a);
        return Map.of("deleted", id);
    }

    /** Live balance / wallet info straight from Deriv. */
    @GetMapping("/{id}/refresh")
    public Map<String, Object> refresh(@AuthenticationPrincipal AuthUser me, @PathVariable Long id) {
        DerivAccount a = own(me, id);
        List<Map<String, Object>> all = deriv.accounts(crypto.decrypt(a.tokenEnc), a.appId);
        Map<String, Object> m = new LinkedHashMap<>(view(a));
        all.stream().filter(x -> a.accountId.equals(x.get("accountId"))).findFirst().ifPresent(x -> {
            m.put("balance", x.get("balance"));
            m.put("currency", x.get("currency"));
        });
        m.put("allAccounts", all.stream().map(x -> Map.of("accountId", String.valueOf(x.get("accountId")),
                "accountType", String.valueOf(x.get("accountType")), "balance", x.get("balance") == null ? 0 : x.get("balance"),
                "currency", String.valueOf(x.get("currency")))).toList());
        return m;
    }

    private DerivAccount own(AuthUser me, Long id) {
        return repo.findByIdAndUserId(id, me.id()).orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Account not found"));
    }
}
