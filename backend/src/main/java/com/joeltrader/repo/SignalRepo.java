package com.joeltrader.repo;

import com.joeltrader.domain.SignalRec;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;
import java.util.Optional;

public interface SignalRepo extends JpaRepository<SignalRec, Long> {
    List<SignalRec> findTop50ByUserIdOrderByCreatedAtDesc(Long userId);
    Optional<SignalRec> findByIdAndUserId(Long id, Long userId);
    void deleteByUserId(Long userId);
}
