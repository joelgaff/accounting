# accounting — working notes for Claude Code

## Stack (fixed)
- Rails 8, **SQLite + Solid suite** (Queue/Cache/Cable). No Postgres/Redis/Sidekiq.
- Hotwire (Turbo + Stimulus). Server-rendered, minimal JS.
- Mail: **letter_opener** in dev, **MailerSend** (SMTP) in prod.
- Deploy: Hatchbox on Hetzner. CDN/DNS: Cloudflare. Storage: Active Storage → Hetzner Object Storage.

## What already exists (built by the foundation script — do NOT recreate)
- **Auth:** Identity/User split, passwordless **6-digit magic-link** login. Working end to end:
  email → code emailed → code entry → session. See `SessionsController`, `Authentication`
  concern, `LoginMailer`, `Identity#issue_login_code!` / `#login_code_valid?`.
- **Tenancy:** `Current.organization` resolved in `ApplicationController#set_organization`
  (single-tenant via `Organization.first` today). `Current.user` set on sign-in.
- Root route → `home#index` (a trivial signed-in landing page).

## Conventions
- **Hotwire-native by default.** Turbo Drive is on via importmap. Reach for `turbo_frame_tag`
  whenever a page updates one region rather than the whole page; use `turbo_stream` responses
  instead of `redirect_to` when appropriate; use Stimulus (`app/javascript/controllers/`) for
  any client-side state (add/remove nested rows, live totals, autocompletes). Full-page
  redirects are the fallback, not the default. Always use `dom_id(record, :section)` for
  frame IDs and stream targets — never handwritten strings.
- **Delegated types** for "same role, different attributes" modeling; keep superclasses lean
  (only universal FKs on the parent), type-specific attributes on the type tables.
  Every ledger transaction is a `Document` (organisation, contact, date, reference, totals,
  line items, payments, attachments) with `delegated_type :documentable` → `Invoice`, `Bill`
  (accrued to AP, takes payments), `Expense` (paid from a bank, Xero's Spend Money),
  `JournalEntry`. A type implements the `Documentable` interface: `ledger_legs(document)`,
  `ledger_description(document)`, `status`, `party_name`, `totals_for(document)`, `line_items?`,
  and for settleable types `settlement_legs(bank_account)` / `settlement_direction`. Document
  posts to the ledger; types never touch it. URLs use the document id (`/invoices/:id`),
  payments nest under `/documents/:id/payments`, and controllers subclass `DocumentsController`.
- **Shared behavior via concerns** with a common interface; let each type define divergent pieces.
- **Name entities, not values** (no `Year` table with a `year` column).
- **Tokenized public shares** (`has_secure_token` + unauthenticated token-scoped controller)
  instead of building logins for external/read-only users.
- **Route reads through `Current.organization`** — never a hardcoded id or `.first` outside
  `set_organization`. Keeps multi-tenancy a one-line change later.
- **Xero-native imports.** Every CSV importer accepts Xero's export format as-is. Header
  normalization strips leading `*` and lowercases. Xero fixtures live in
  `test/fixtures/files/xero/` and drive service tests. Full history comes from Xero's
  Journal report (`Imports::XeroJournalsService`): it posts everything the invoice and
  bill importers don't (spend/receive money, transfers, manual journals, conversion
  balances) and skips ACCREC/ACCPAY/payment journals unless told otherwise.

## Xero migration toolkit (rake)
- `bin/rails 'xero:import[/path/to/bundle]'`, `xero:status`, `xero:reset` (keeps the chart),
  `'xero:reset[everything]'`. `DRY_RUN=1` previews any of them; production reset needs
  `CONFIRM=<org name>`. `bin/xero-prod <status|import DIR|reset [scope]>` rsyncs a bundle
  to the Hatchbox server and runs the same tasks there.

## Run locally
- `bin/dev` boots the Launchpad SSO hub (`../launchpad`, port 3000) and this app (port 3001)
  together via `Procfile.dev`. Open **http://accounting.lvh.me:3001** — the SSO cookie is scoped
  to `.lvh.me`, so `localhost` never signs in (a dev-only middleware redirects it for you).
- Override the hub checkout with `LAUNCHPAD_DIR=/path bin/dev`.

## Deferred until actually needed
- Multi-tenant membership/roles/switching (single-tenant now; structure is ready).
- Stripe billing (add when the app monetizes).

## Build the domain on top
Add domain models/controllers/views. The foundation (auth, tenancy, mail) is done.

## Run CI locally before pushing

To avoid failing on GitHub Actions, get this repo's CI green locally first. Work in this order; stop and show any change that isn't purely mechanical.

1. **Lint** (`rubocop-rails-omakase`) — `bin/rubocop`. If it reports offenses, run the SAFE autocorrect only: `bin/rubocop -a` (never `-A` / unsafe). These are style-only (single vs double quotes, array-bracket spacing, trailing whitespace, final newlines); confirm `bin/rubocop` then reports zero offenses. No logic changes.
2. **Tests** — `bin/rails db:test:prepare test`. Two recurring failures have test-env-only fixes (never touch production paths):
   - *"Missing Active Record encryption credential: primary_key"* → add dummy AR encryption keys in `config/environments/test.rb` (real keys still come from credentials/ENV when present).
   - *"Google API error: request denied" / geocoding failures* → route Geocoder through its built-in `:test` lookup in the test environment so no real Google call is made.
   - A genuine missing-coverage gap or real code bug gets fixed here, not papered over.
3. **Security / deps** — `bundle exec bundler-audit check --update` (fix real CVEs by bumping the gem, don't hand-edit the lockfile to hide a vuln), `bin/brakeman --no-pager` (triage low-confidence pre-existing warnings, don't blindly silence), `bin/importmap audit`.
4. **System tests** (only if asked) — `bin/rails test:system` is browser-based and app-specific (e.g. a location picker not populating in headless mode). Report as a separate known-red item; don't chase unless asked.

Rules: one small commit per concern (lint separate from test-config separate from deps). The bar is: lint clean, unit + integration tests green with NO real secrets required, deps audited.
