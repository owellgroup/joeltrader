package com.joeltrader.domain;

import jakarta.persistence.*;
import java.time.Instant;

@Entity
@Table(name = "trades", indexes = {@Index(columnList = "userId,closedAt"), @Index(columnList = "tradeRef", unique = true)})
public class Trade {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY) public Long id;
    public Long userId;
    public String accountId;
    public String tradeRef;
    public String basketId;
    public String symbol;
    public String direction;
    public String kind;                     // AUTO | NEWS | ADOPTED
    public Double stake;
    public Integer score;
    @Column(columnDefinition = "text") public String reason;
    public Integer durationMin;
    public Double entry, sl, tp;
    public Double profit;
    public Double sellPrice;
    public String status = "OPEN";          // OPEN | WON | LOST
    public Instant openedAt;
    public Instant closedAt;
}
