# Deploying Partita Doppia

Any host that runs Rails 8 with SQLite works. What the app needs:

1. `RAILS_MASTER_KEY` in the environment; everything else in the encrypted
   credentials (see `config/credentials.yml.example`): `secret_key_base`,
   `active_record_encryption`, `app.host`, `smtp`, and optionally `xero` and
   `launchpad`.
2. A persistent `storage/` directory (the SQLite databases and Active Storage).
3. The Solid Queue worker (`bin/jobs`, or `SOLID_QUEUE_IN_PUMA=true`) for the
   nightly SimpleFIN sync, Xero imports and email.
4. `bin/rails db:prepare` on each deploy.

Then open the site: with no users it shows the setup page.

---

## Joel's deployment — Hatchbox on Hetzner

Domain: `accounting.enduranceevolution.com`. Sign-in is the Launchpad hub
(`launchpad:` block in credentials; app key `partita_doppia`, the old
`accounting` key still accepted). The notes below are the original checklist.

## Before first deploy

- [x] ~~Rotate `RAILS_MASTER_KEY`~~ Decided 2026-09-14 not to rotate.
  - `rm config/credentials.yml.enc config/master.key`
  - `EDITOR=nvim bin/rails credentials:edit` (regenerates both)
  - Commit the new `config/credentials.yml.enc`
  - Set the new `config/master.key` value in the Hatchbox env panel as `RAILS_MASTER_KEY`

- [ ] **Wire MailerSend SMTP via credentials**
  - `bin/rails credentials:edit` → add:
    ```yaml
    smtp:
      user_name: <mailersend username>
      password: <mailersend password / api token>
      address: smtp.mailersend.net
      port: 587
    ```
  - Uncomment the `config.action_mailer.smtp_settings = { ... }` block in `config/environments/production.rb`
  - Verify DNS (SPF/DKIM) for `enduranceevolution.com` in MailerSend dashboard

- [ ] **Wire Hetzner Object Storage via credentials**
  - `bin/rails credentials:edit` → add:
    ```yaml
    hetzner:
      access_key_id: <key>
      secret_access_key: <secret>
    ```
  - In `config/storage.yml`, add a `hetzner` service (S3-compatible, `endpoint:` set to the Hetzner Object Storage endpoint, `region:`, `bucket:`)
  - Flip `config.active_storage.service = :hetzner` in `config/environments/production.rb`
  - Create the bucket in Hetzner console

- [ ] **DNS**
  - Cloudflare A/AAAA record: `accounting.enduranceevolution.com` → Hatchbox server IP
  - Decide TLS mode: Hatchbox Let's Encrypt (DNS-only in Cloudflare) or Cloudflare Full/Strict with an origin cert

## First deploy

- [ ] Add app in Hatchbox (name `partita_doppia`), connect `joelgaff/partita_doppia` repo, `master` branch
- [ ] Set env vars in Hatchbox: `RAILS_MASTER_KEY` (only one required beyond platform defaults)
- [ ] Deploy
- [ ] Watch initial migration + Solid Queue/Cache/Cable table creation
- [ ] Confirm `/up` returns 200

## Smoke test in production

- [ ] Magic-link login end-to-end (email → 6-digit code → session) using a real inbox
- [ ] Import a Xero Chart of Accounts CSV
- [ ] Create an invoice with line items → PDF renders → email delivery works
- [ ] Attach a receipt to an expense → confirms Active Storage → Hetzner
- [ ] Import a bank CSV → reconcile a transaction
- [ ] View P&L, Balance Sheet, AR/AP aging

## Bank feed and nightly jobs

- [ ] **Active Record encryption keys** are in `config/credentials.yml.enc` (`active_record_encryption:` block); the bank feed's access URL is encrypted with them. Nothing to set on Hatchbox beyond `RAILS_MASTER_KEY`.
- [x] **Solid Queue runs in production** (a `solid-queue-fork-supervisor` with dispatcher, worker and scheduler is up on the Hatchbox host; checked 2026-09-14). The nightly `simplefin_sync` task in `config/recurring.yml` registers itself on the next deploy. Verify with `bin/rails runner 'puts SolidQueue::RecurringTask.pluck(:key)'` on the server and check `SolidQueue::RecurringExecution` after 4am UTC.
- [ ] **Xero API import.** Create an app at developer.xero.com (Web app; redirect URI
  `https://accounting.enduranceevolution.com/settings/xero/callback`; scopes are requested by the app).
  Put its client id and secret in the credentials under `xero:` (`client_id`, `client_secret`), deploy,
  then Settings → Xero → Connect, and Run import. Re-running is safe; it updates in place.
- [ ] Connect SimpleFIN under Settings → Bank feed (setup token from bridge.simplefin.org), map accounts, Sync now.

## Nice-to-have (post-launch, non-blocking)

- [ ] Cloudflare caching rules (bypass for `/rails/active_storage/*` if needed)
- [ ] Uptime monitoring hitting `/up`
- [ ] Off-site backup of `storage/production*.sqlite3` (Hatchbox has snapshots; add Dropbox/off-Hetzner mirror for paranoia)

---

Once every box is checked and the app has run cleanly for a few days, delete this file.
