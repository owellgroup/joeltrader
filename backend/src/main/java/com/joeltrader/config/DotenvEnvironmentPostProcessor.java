package com.joeltrader.config;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.env.EnvironmentPostProcessor;
import org.springframework.core.env.ConfigurableEnvironment;
import org.springframework.core.env.MapPropertySource;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Loads the repo-root {@code .env} when the JVM is started outside Docker
 * ({@code mvn spring-boot:run}, IDE). Existing OS / Dokploy env vars win.
 */
public class DotenvEnvironmentPostProcessor implements EnvironmentPostProcessor {

    @Override
    public void postProcessEnvironment(ConfigurableEnvironment env, SpringApplication app) {
        for (Path candidate : candidates()) {
            if (!Files.isRegularFile(candidate)) continue;
            Map<String, Object> values = parse(candidate);
            if (!values.isEmpty()) {
                env.getPropertySources().addLast(new MapPropertySource("dotenvFile", values));
                return;
            }
        }
    }

    private static List<Path> candidates() {
        Path cwd = Path.of(System.getProperty("user.dir", ".")).toAbsolutePath().normalize();
        Path parent = cwd.getParent() != null ? cwd.getParent().resolve(".env") : cwd.resolve(".env");
        return List.of(
                cwd.resolve(".env"),
                parent,
                Path.of(".env").toAbsolutePath().normalize(),
                Path.of("..", ".env").toAbsolutePath().normalize()
        );
    }

    static Map<String, Object> parse(Path file) {
        Map<String, Object> out = new LinkedHashMap<>();
        try {
            for (String raw : Files.readAllLines(file, StandardCharsets.UTF_8)) {
                String line = raw.strip();
                if (line.isEmpty() || line.startsWith("#")) continue;
                if (line.regionMatches(true, 0, "export ", 0, 7)) line = line.substring(7).strip();
                int eq = line.indexOf('=');
                if (eq <= 0) continue;
                String key = line.substring(0, eq).strip();
                String value = unquote(line.substring(eq + 1).strip());
                if (!key.isEmpty()) out.put(key, value);
            }
        } catch (Exception ignored) {
            // fall through: OS / Dokploy environment still applies
        }
        return out;
    }

    private static String unquote(String value) {
        if (value.length() >= 2) {
            char a = value.charAt(0);
            char b = value.charAt(value.length() - 1);
            if ((a == '"' && b == '"') || (a == '\'' && b == '\'')) {
                return value.substring(1, value.length() - 1);
            }
        }
        return value;
    }
}
