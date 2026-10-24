package com.joeltrader.domain;

import jakarta.persistence.*;
import java.time.Instant;

@Entity
@Table(name = "app_users")
public class User {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY) public Long id;
    @Column(unique = true, nullable = false) public String email;
    public String name;
    @Column(nullable = false) public String passwordHash;
    public String role = "ADMIN";           // SUPER_ADMIN | ADMIN
    public boolean enabled = true;
    public boolean mustChangePassword = false;
    public Instant createdAt = Instant.now();
}
