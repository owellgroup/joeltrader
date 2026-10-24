package com.joeltrader.service;

import com.joeltrader.domain.User;
import com.joeltrader.repo.UserRepo;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.CommandLineRunner;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;

/** Creates the super admin on first start. The password must be changed at first login. */
@Component
public class DataSeeder implements CommandLineRunner {
    private static final Logger log = LoggerFactory.getLogger(DataSeeder.class);
    private final UserRepo users;
    private final PasswordEncoder enc;
    private final String email, password;

    public DataSeeder(UserRepo users, PasswordEncoder enc, @Value("${app.super-admin-email}") String email,
                      @Value("${app.super-admin-password}") String password) {
        this.users = users; this.enc = enc; this.email = email; this.password = password;
    }

    @Override
    public void run(String... args) {
        if (users.findByEmailIgnoreCase(email).isPresent()) return;
        User u = new User();
        u.email = email.toLowerCase();
        u.name = "Super Admin";
        u.role = "SUPER_ADMIN";
        u.passwordHash = enc.encode(password);
        u.mustChangePassword = true;
        users.save(u);
        log.info("Seeded super admin {}", email);
    }
}
