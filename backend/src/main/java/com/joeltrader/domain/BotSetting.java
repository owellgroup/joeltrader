package com.joeltrader.domain;

import jakarta.persistence.*;
import java.time.Instant;

@Entity
@Table(name = "bot_settings")
public class BotSetting {
    @Id public Long userId;
    public boolean running = false;
    public Long derivAccountId;
    @Column(columnDefinition = "text") public String configJson = "{}";
    public Double lastBalance;
    public Double dayPnl;
    public Instant lastBalanceAt;
    public BotSetting() {}
    public BotSetting(Long userId) { this.userId = userId; }
}
