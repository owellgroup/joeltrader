package com.joeltrader.repo;

import com.joeltrader.domain.WatchSymbol;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;
import java.util.Optional;

public interface WatchRepo extends JpaRepository<WatchSymbol, Long> {
    List<WatchSymbol> findByUserIdOrderBySymbolAsc(Long userId);
    Optional<WatchSymbol> findByUserIdAndSymbol(Long userId, String symbol);
    void deleteByUserId(Long userId);
}
