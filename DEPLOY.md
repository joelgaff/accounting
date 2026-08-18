# Deploy checklist — Hatchbox on Hetzner

Domain: `accounting.enduranceevolution.com`

Everything Slice A–M is shipped. This file tracks the remaining work to get the app live and drop it once done. Check items off in-place as you complete them.

## Before first deploy

- [ ] **Rotate `RAILS_MASTER_KEY`** (the current one was pasted into chat — treat as leaked)
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

- [ ] Add app in Hatchbox, connect `joelgaff/accounting` repo, `master` branch
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

## Nice-to-have (post-launch, non-blocking)

- [ ] Cloudflare caching rules (bypass for `/rails/active_storage/*` if needed)
- [ ] Uptime monitoring hitting `/up`
- [ ] Off-site backup of `storage/production*.sqlite3` (Hatchbox has snapshots; add Dropbox/off-Hetzner mirror for paranoia)

---

Once every box is checked and the app has run cleanly for a few days, delete this file.
