package com.joeltrader.domain;

import jakarta.persistence.*;
import java.time.Instant;

@Entity
@Table(name = "signals", indexes = @Index(columnList = "userId,createdAt"))
public class SignalRec {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY) public Long id;
    public Long userId;
    public String symbol;
    public String direction;
    public Double entry, sl, tp1, tp2, rr;
    public Integer score;
    public String tf;
    public String source;                   // WATCH | MANUAL
    @Column(columnDefinition = "text") public String reasons;
    public boolean emailed = false;
    public Instant createdAt = Instant.now();
}
