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
- **Shared behavior via concerns** with a common interface; let each type define divergent pieces.
- **Name entities, not values** (no `Year` table with a `year` column).
- **Tokenized public shares** (`has_secure_token` + unauthenticated token-scoped controller)
  instead of building logins for external/read-only users.
- **Route reads through `Current.organization`** — never a hardcoded id or `.first` outside
  `set_organization`. Keeps multi-tenancy a one-line change later.
- **Xero-native imports.** Every CSV importer accepts Xero's export format as-is. Header
  normalization strips leading `*` and lowercases. Xero fixtures live in
  `test/fixtures/files/xero/` and drive service tests.

## Deferred until actually needed
- Multi-tenant membership/roles/switching (single-tenant now; structure is ready).
- Stripe billing (add when the app monetizes).

## Build the domain on top
Add domain models/controllers/views. The foundation (auth, tenancy, mail) is done.
