package com.joeltrader.repo;

import com.joeltrader.domain.Trade;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import java.time.Instant;
import java.util.List;
import java.util.Optional;

public interface TradeRepo extends JpaRepository<Trade, Long> {
    Optional<Trade> findByTradeRef(String ref);
    Page<Trade> findByUserIdOrderByOpenedAtDesc(Long userId, Pageable p);
    List<Trade> findByUserIdAndStatusOrderByOpenedAtDesc(Long userId, String status);
    List<Trade> findByUserIdAndStatusNotAndClosedAtAfterOrderByClosedAtAsc(Long userId, String status, Instant since);
    void deleteByUserId(Long userId);
}
