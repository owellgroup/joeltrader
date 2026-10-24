# joelTrader

Deriv trading terminal: auto-trading bot, signal provider with a TradingView-style chart, gold NFP news trader, performance analytics and email reports. Multi-admin, each admin sees only their own data.

```
joeltrader/
  docker-compose.yml   Spring Boot API + Python engine  (deploy this on Dokploy)
  .env                 real secrets — never commit
  .env.example         same keys, copy into Dokploy Environment
  backend/             Java 21 / Spring Boot 3
  engine/              Python / FastAPI
  frontend/            Flutter app — run locally, talks to the remote API
```

Public URL after deploy: **http://145.241.187.174:8181**

The Flutter app never talks to the Python engine. It calls the Java API on port 8181. The API calls the engine on the private Docker network (`http://engine:8000`). Only port **8181** is published on the host so existing Dokploy containers keep their ports.

---

## 1. One-time: environment file

On your laptop, the repo already has `.env`. If you clone fresh:

```bash
cp .env.example .env
```

`application.properties` has **no secrets**. Spring reads `.env` automatically when you run the backend locally, and Docker Compose / Dokploy inject the same keys as environment variables.

| Key | What it is |
|---|---|
| `DB_URL` / `DB_USER` / `DB_PASSWORD` | Hosted Postgres at `84.8.131.140:5432/wayaspot` |
| `JWT_SECRET` | Generated HS256 signing key (48 random bytes, hex). Login issues a JWT valid 30 days |
| `APP_ENC_KEY` | Encrypts Deriv tokens in the database. Do not rotate after accounts are linked |
| `INTERNAL_KEY` | Shared secret between backend and engine |
| `ENGINE_URL` | `http://engine:8000` inside Docker |
| `MAIL_*` | Resend SMTP |
| `SERVER_PORT` | `8181` — the only host port this stack uses |

Generated `JWT_SECRET` (already in `.env` and `.env.example`):

```
cebe6f6a3653fbc31c519c32d1314c7495d6cb12a5fd3de1e8f510c02fa31a8f68c7ebe775c81dcb69a0195fba99b1aa
```

A user JWT is **not** baked in. After deploy, sign in at `/api/auth/login` and the API returns `{"token":"<jwt>", "user":{...}}`.

---

## 2. Server firewall (145.241.187.174)

Other containers already occupy some ports. This stack only needs inbound **8181**. Leave 80/443/3000 and the rest alone.

```bash
sudo ufw allow 8181/tcp
sudo ufw status
```

The server must also reach:

* `84.8.131.140:5432` — Postgres
* `smtp.resend.com:587` — mail
* `api.derivws.com` — Deriv

Do **not** open 8000 (engine) or 5432 (no local database).

---

## 3. Deploy backend + engine on Dokploy

1. Push this repo to Git (GitHub / GitLab / Gitea). `.env` stays untracked. `.env.example` is the checklist.
2. In Dokploy: **Create project** → **Create service** → **Compose**.
3. Connect the git repo. Compose file path: `docker-compose.yml` (repo root).
4. Open **Environment** and paste every line from `.env.example` (or from your local `.env`). Save.
5. Confirm the compose file maps **only** `8181:8181`. Do not add extra port publishes.
6. If Dokploy offers a domain / Traefik toggle, you can leave it off. Raw IP access uses the published port, not a proxy hostname.
7. Deploy. First build pulls Maven + Python images and takes several minutes.
8. From any browser or the server itself:

```bash
curl http://145.241.187.174:8181/health
```

Expected:

```json
{"ok":true,"service":"joeltrader-backend"}
```

9. Super admin (seeded on first start): `joel@wayaspot.com` / `Admin@123`. You are forced to change that password at first login.

If the health check fails:

* Dokploy logs for `backend` — missing env vars fail fast (`set JWT_SECRET in .env / Dokploy`).
* Confirm nothing else on the server is already bound to host 8181: `sudo ss -tlnp | grep 8181`.
* Confirm the container is listening: `docker ps` should show `0.0.0.0:8181->8181/tcp` on the backend.

---

## 4. Run the Flutter app locally (against the live API)

The default API URL is already `http://145.241.187.174:8181`.

```bash
cd frontend
flutter create .            # one time: generates android/ios/web/windows (keeps lib/ and pubspec.yaml)
flutter pub get

# Chrome
flutter run -d chrome --dart-define=API_URL=http://145.241.187.174:8181

# Windows desktop
flutter run -d windows --dart-define=API_URL=http://145.241.187.174:8181
```

Login stays active for 30 days and is refreshed each time the app opens.

`APP_CORS=*` lets Flutter web on `localhost` call the remote API.

---

## 5. Optional: run the backend on your laptop

Needs Java 21, Maven, and the `.env` at the repo root. Postgres is remote, so Docker is not required.

```bash
cd backend
mvn spring-boot:run
```

The dotenv loader finds `../.env`. For a fully local engine as well:

```bash
cd engine
pip install -r requirements.txt
# set INTERNAL_KEY and BACKEND_URL=http://localhost:8181 in the shell, then:
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

And temporarily set `ENGINE_URL=http://localhost:8000` in `.env` (put it back to `http://engine:8000` before the next Dokploy deploy).

---

## 6. First use (do it on DEMO)

1. Sign in, change the password.
2. Deriv: create an app + a Personal Access Token (scope `trade`) at developers.deriv.com.
3. **Accounts** → Link account → paste App ID + token → pick the demo account.
4. **Auto Trader** → select the account → **Trade now**. Real accounts also need the "I allow real-money trading" box.
5. **Charts** → pick a symbol → **Analyze automatically** (signal drawn on chart and emailed).

---

## How the bot decides (and what it cannot promise)

* Scan: every ~45 s ranks open forex/gold on H1 and fully analyses every open synthetic (Volatility, Boom, Crash and the rest of that list — the log's "20 synthetics" are all checked, not a shortlist). The best 4 forex names are checked as well. The highest score above 72 is the trade.
* Forex/gold entry needs: D1/H4 not against the trade, price at an H1 zone, an M5 trigger, a sensible stop and at least 1.5R. Boom, Crash and Volatility use their own rule: a pullback (or H1 zone) plus an M5 trigger. Boom prefers buys, Crash prefers sells. Score threshold: 72 for every market (adjustable). Most scans correctly find nothing.
* Bulk trades = several identical contracts, sized by `risk.plan_basket`: total basket stake <= `risk_pct` of balance (default 5 %), total open stake <= 15 %, one contract <= 10 %. A $10 account gets 1 contract of about $0.50; $1000 gets up to 10.
* Exit: the whole basket closes at +25 % of its stake or -50 % (basket stop), before high-impact news, on the daily loss limit (10 %), or on the drawdown kill switch (25 % from peak). 3 losing baskets in a row pause trading for 60 min.
* Gold NFP trader: 15 min before the release it analyses gold, then enters only if gold moves >= 1x M1 ATR after the release (1.6x if against the H4 bias), with a smaller basket.
* Daily email report, signal emails, basket-closed and halt alerts.

**No strategy can guarantee profit or an account that never loses.** On Deriv options the worst case per contract is the stake, so the limits above cap the loss per basket, per day and overall, but losing streaks will happen. Boom drifts up and Crash drifts down, with sharp spikes the other way; Volatility 75 does not trend like forex. Run on demo for weeks and read the Performance page before risking real money.

---

## Verified vs. not verified

Verified here: Python engine unit tests and an end-to-end bot lifecycle test against a fake Deriv socket (`cd engine && pytest`).

**Not compiled or run here:** the Spring Boot backend (no Maven access in the build sandbox) and the Flutter app (no Flutter SDK). Expect to fix a few compile errors on first build.

**Not tested against live Deriv:** Deriv's new options API renames the proposal field `symbol` to `underlying_symbol` (the engine sends that, and retries `symbol` if a socket still wants the old name). Market data still uses `ticks_history`. Account-ID format (demo vs real) detection is in `backend/.../service/DerivRest.java`. Creating a new Deriv account from inside the app is not included; link existing accounts instead. "Market news" is the economic calendar (ForexFactory weekly feed); Deriv has no headline news API.
