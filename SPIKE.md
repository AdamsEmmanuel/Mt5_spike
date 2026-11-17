# MT5 on Render: feasibility spike

Question this spike answers: can a free Render container run Headway MT5 under Wine,
log in, receive EURUSD data, and stay within 512 MB of RAM?

It does NOT trade and does NOT include the trading bot. Once it passes, the bot is
connected to the MT5 terminal through a small bridge (next step).

## Before you start

1. Download the Headway MT5 Windows setup from Headway's official site and put the
   `.exe` in `installer/`. Do not guess the download URL.
2. Get the exact server name from the MT5 login dialog (for example, `Headway-Demo`
   or whatever your account shows). It must match exactly.
3. Generate a secret key on any device:
   `python -c "import secrets;print(secrets.token_urlsafe(32))"`

## Deploy

1. Create a private GitHub repo (e.g. `mt5-spike`) and push this whole folder
   (including `installer/`).
2. On dashboard.render.com: **New > Web Service** > connect the repo.
   Runtime: **Docker**. Instance type: **Free**.
3. Environment variables:

   | Variable | Value |
   |---|---|
   | `MT5_LOGIN` | your Headway account number |
   | `MT5_PASSWORD` | your trading password (set as a secret, never in chat or code) |
   | `MT5_SERVER` | exact server name, e.g. `Headway-Demo` |
   | `MT5_SYMBOL` | optional; leave empty to test `EURUSD`, `EURUSD.r`, `EURUSDm` |
   | `SECRET_KEY` | the key you generated |

4. Deploy. The first build takes a while because it installs Wine, Python and MT5.
   If the build fails, the log names the failed stage (Python install, MetaTrader5
   import, or the terminal's silent install).
5. When the service is live:

   ```bash
   curl https://<service>.onrender.com/health
   curl -H "X-Secret-Key: <SECRET_KEY>" https://<service>.onrender.com/report
   ```

   `/report` returns the login result, a memory log, and the login output.

## Pass criteria (all must hold)

- `login.json`: `initialized` true, `login_matches` true, `terminal_connected` true.
- `symbol_with_tick` is set and `m15_bars_received` is at least 200.
- Memory samples in `mem.log` stay under 512 MB across at least 30 minutes.
- Redeploy the service. Login succeeds again without manual steps within 5 minutes.
- No out-of-memory restarts in Render's event log.

## What a failure means

| Result | Meaning | Next step |
|---|---|---|
| Build fails at Python or MetaTrader5 stage | Wine or pip issue | Send me the build log |
| Build fails at terminal stage | Installer doesn't support `/S` | Tell me the installer's silent switch |
| `initialized` false, `last_error` timeout | Terminal didn't log in | Check login, server name, password; check `login.out` |
| Login works but memory over 512 MB or restarts | Free tier too small | Option 1 is not viable on free; see the note in the reply |
| Login works, no tick | Market closed, or symbol name wrong | Check `symbols` in `login.json` |

## Known risks

- Free Render has 512 MB. Wine plus the MT5 terminal plus two Python processes may not
  fit. The spike exists to measure this, not to assume it.
- Debian's Wine version is whatever Debian bookworm ships. MT5 generally runs on it,
  but if login hangs, a newer Wine is the first thing to try.
- Passwords reach the process only through environment variables. They are not in
  the image, the repo or the logs.
