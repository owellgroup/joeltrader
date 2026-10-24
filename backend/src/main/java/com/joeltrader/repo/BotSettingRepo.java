package com.joeltrader.repo;

import com.joeltrader.domain.BotSetting;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface BotSettingRepo extends JpaRepository<BotSetting, Long> {
    List<BotSetting> findByRunningTrue();
}
