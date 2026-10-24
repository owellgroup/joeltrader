package com.joeltrader.security;

import com.joeltrader.repo.UserRepo;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.filter.OncePerRequestFilter;
import java.io.IOException;
import java.util.List;

/** Not a @Component on purpose: it is registered only inside the security chain. */
public class JwtFilter extends OncePerRequestFilter {
    private final JwtService jwt;
    private final UserRepo users;

    public JwtFilter(JwtService jwt, UserRepo users) { this.jwt = jwt; this.users = users; }

    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
            throws ServletException, IOException {
        String h = req.getHeader("Authorization");
        if (h != null && h.startsWith("Bearer ")) {
            try {
                Long id = jwt.parse(h.substring(7));
                users.findById(id).filter(u -> u.enabled).ifPresent(u -> {
                    var au = new AuthUser(u.id, u.email, u.role);
                    var auth = new UsernamePasswordAuthenticationToken(au, null,
                            List.of(new SimpleGrantedAuthority("ROLE_" + u.role)));
                    SecurityContextHolder.getContext().setAuthentication(auth);
                });
            } catch (Exception ignored) { /* invalid or expired token -> stays unauthenticated */ }
        }
        chain.doFilter(req, res);
    }
}
