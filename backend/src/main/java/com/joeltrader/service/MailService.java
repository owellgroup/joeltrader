package com.joeltrader.service;

import com.joeltrader.domain.SignalRec;
import jakarta.mail.internet.MimeMessage;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mail.javamail.MimeMessageHelper;
import org.springframework.stereotype.Service;
import java.util.Locale;
import java.util.Map;

@Service
public class MailService {
    private static final Logger log = LoggerFactory.getLogger(MailService.class);
    private final ObjectProvider<JavaMailSender> sender;
    private final String from;
    private final boolean configured;

    public MailService(ObjectProvider<JavaMailSender> sender, @Value("${app.mail-from}") String from,
                       @Value("${spring.mail.host:}") String host) {
        this.sender = sender; this.from = from; this.configured = host != null && !host.isBlank();
    }

    public void send(String to, String subject, String html) {
        java.util.concurrent.CompletableFuture.runAsync(() -> doSend(to, subject, html));
    }

    private void doSend(String to, String subject, String html) {
        JavaMailSender s = sender.getIfAvailable();
        if (!configured || s == null) { log.info("[mail not configured] to={} subject={}", to, subject); return; }
        try {
            MimeMessage m = s.createMimeMessage();
            MimeMessageHelper h = new MimeMessageHelper(m, "UTF-8");
            h.setFrom(from); h.setTo(to); h.setSubject(subject); h.setText(html, true);
            s.send(m);
        } catch (Exception e) { log.warn("mail to {} failed: {}", to, e.getMessage()); }
    }

    static String esc(String s) {
        return s == null ? "" : s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;");
    }

    static String money(Double v) { return v == null ? "-" : String.format(Locale.US, "%+.2f", v); }

    public static String wrap(String title, String body) {
        return "<div style='background:#0d1117;padding:24px;font-family:Segoe UI,Arial,sans-serif'>"
                + "<div style='max-width:640px;margin:auto;background:#161b22;border:1px solid #30363d;border-radius:12px;overflow:hidden'>"
                + "<div style='background:#0b3dff;padding:16px 24px;color:#fff;font-size:18px;font-weight:700'>joelTrader</div>"
                + "<div style='padding:24px;color:#e6edf3;font-size:14px;line-height:1.6'><h2 style='margin:0 0 12px;color:#fff'>"
                + esc(title) + "</h2>" + body + "</div>"
                + "<div style='padding:14px 24px;color:#8b949e;font-size:12px;border-top:1px solid #30363d'>"
                + "Automated message. Trading involves risk; setup scores measure confluence, not probability of profit.</div></div></div>";
    }

    public static String row(String k, String v) {
        return "<tr><td style='padding:6px 12px 6px 0;color:#8b949e'>" + esc(k) + "</td><td style='padding:6px 0;color:#fff'>" + v + "</td></tr>";
    }

    public void signal(String to, SignalRec s) {
        boolean buy = "BUY".equals(s.direction);
        String col = buy ? "#3fb950" : "#f85149";
        String body = "<p style='font-size:20px;margin:0 0 12px'><b style='color:" + col + "'>" + esc(s.direction) + "</b> " + esc(s.symbol) + "</p>"
                + "<table>" + row("Entry", String.valueOf(round(s.entry))) + row("Stop loss", String.valueOf(round(s.sl)))
                + row("Take profit 1", String.valueOf(round(s.tp1))) + row("Take profit 2", String.valueOf(round(s.tp2)))
                + row("Risk : reward", String.valueOf(s.rr)) + row("Setup score", s.score + " / 100") + row("Entry timeframe", esc(s.tf)) + "</table>"
                + "<h3 style='color:#fff'>Why this setup</h3><div>" + esc(s.reasons).replace("\n", "<br>• ") + "</div>";
        send(to, "Signal: " + s.direction + " " + s.symbol, wrap("Trade signal", body));
    }

    public static Double round(Double v) { return v == null ? null : Math.round(v * 100000d) / 100000d; }

    public void basket(String to, Map<String, Object> d) {
        double pnl = ((Number) d.getOrDefault("pnl", 0)).doubleValue();
        String col = pnl >= 0 ? "#3fb950" : "#f85149";
        String body = "<p style='font-size:20px'><b style='color:" + col + "'>" + money(pnl) + "</b> on " + esc(String.valueOf(d.get("symbol"))) + "</p>"
                + "<table>" + row("Basket stake", String.valueOf(d.get("stake"))) + row("Basket", esc(String.valueOf(d.get("basketId")))) + "</table>"
                + "<p>The bot closed this basket and is scanning for the next entry.</p>";
        send(to, "Basket closed " + money(pnl) + " " + d.get("symbol"), wrap("Trade basket closed", body));
    }

    public void alert(String to, String title, String text) {
        send(to, "joelTrader: " + title, wrap(title, "<p>" + esc(text) + "</p>"));
    }
}
