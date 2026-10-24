package com.joeltrader.domain;

import jakarta.persistence.*;

@Entity
@Table(name = "watch_symbols", uniqueConstraints = @UniqueConstraint(columnNames = {"userId", "symbol"}))
public class WatchSymbol {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY) public Long id;
    public Long userId;
    public String symbol;
    public boolean favorite = true;
    public boolean signals = false;         // engine scans this symbol and emails clean setups
}
