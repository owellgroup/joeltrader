package com.joeltrader.domain;

import jakarta.persistence.*;
import java.time.Instant;

@Entity
@Table(name = "deriv_accounts", indexes = @Index(columnList = "userId"))
public class DerivAccount {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY) public Long id;
    public Long userId;
    public String label;
    public String accountId;
    public String accountType = "DEMO";     // DEMO | REAL
    public String appId;
    @Column(length = 2000) public String tokenEnc;
    public String currency;
    public Instant createdAt = Instant.now();
}
