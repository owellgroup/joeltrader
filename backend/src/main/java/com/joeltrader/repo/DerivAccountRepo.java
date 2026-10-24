package com.joeltrader.repo;

import com.joeltrader.domain.DerivAccount;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;
import java.util.Optional;

public interface DerivAccountRepo extends JpaRepository<DerivAccount, Long> {
    List<DerivAccount> findByUserIdOrderByIdAsc(Long userId);
    Optional<DerivAccount> findByIdAndUserId(Long id, Long userId);
    void deleteByUserId(Long userId);
}
