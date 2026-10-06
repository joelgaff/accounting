# Partita Doppia (formerly Ledger): open-source plan

Decided 2026-10-06. Not started. Production stays on Launchpad throughout; every
step below can ship on its own.

## Order of work

1. **Settings reorganisation.** Done 2026-10-06: Import and Tax rates left the
   sidebar; Settings is a stack of panels (Organisation, Dashboard accounts,
   Connections, Books, Imports and data, Appearance). Importer services, tests
   and the rake bundle task untouched.
2. **Sign-in: magic codes by default, Launchpad as an option.** Done 2026-10-06
   (plan below, all eight commits, including the You panel and People page);
   hub and host settings moved into credentials; `config/credentials.yml.example`
   and the README written in the same pass.
3. **Fixture pass.** Test fixtures lose real customer and vendor names.
   (The credentials example is done.)
4. **Docs and license.** README for self-hosters (setup, Xero app registration
   with the March 2026 scope rules and the conversion-balance gap, SimpleFIN,
   stated assumptions: USD, single sales-tax rate, calendar year, single
   organisation). License (MIT or AGPL, Joel to pick). CONTRIBUTING note on the
   pre-push CI hook. DEPLOY.md and CLAUDE.md separate app guidance from Joel's
   Hatchbox deployment; `bin/xero-prod` is documented as his.
5. Publish.

Left alone: Hatchbox deploy, the rake bundle importer, the design.

## Sign-in plan

**Goal.** Two ways in, chosen by configuration, with no change for Joel: a
passwordless magic-code login that any self-hoster gets out of the box, and the
Launchpad hub when its settings are present. Nothing else in the app knows which
one is active.

### 1. Strategy selection

- One place decides: if the credentials hold a `launchpad` block (hub URL, JWT
  secret, issuer, cookie domain), the app runs Launchpad mode; otherwise local
  mode. No separate flag to forget.
- The base controller keeps a single "require authentication" step that
  delegates to the active strategy. Both set `Current.user`.
- Joel's domain values move out of the production environment file into that
  credentials block, with the same values, so his deploy is unchanged.

### 2. Data model

- Users: the Launchpad id becomes optional. Email stays the human identifier and
  gets a uniqueness constraint. Theme and name stay as they are.
- Sessions use the Rails cookie session store the way rails-now does:
  `session[:user_id]`, `reset_session` on sign-in and sign-out. No sessions
  table in this pass; server-side revocation can come later as a table if
  listing and ending other sessions is ever wanted.
- Login codes on the user record: `login_code_digest` (bcrypt) and
  `login_code_expires_at`, as in rails-now, plus two additions it does not have:
  `login_code_attempts` and `login_code_sent_at` for the limits in section 6.
  Nothing is ever stored in plain text.

### 3. Flows in local mode

- **Sign in.** Enter an email. If a user exists, a code is emailed; the page moves
  to a code entry either way, so the form never reveals which emails are
  registered. The email also carries a one-click link with the code in it. A
  correct code within ten minutes and five attempts creates the session. Codes
  are single-use.
- **First run.** With no users in the database, every path lands on a setup page:
  organisation name and your email. The code proves the email, then the
  organisation and the first user are created together. The page stops existing
  the moment a user does, which is the main thing the tests have to prove.
- **Adding people.** A People section under Settings where an existing user adds
  an email and name. The new person gets a welcome email with a sign-in link.
  Users can be removed, except yourself.
- **Sign out.** Deletes the session row and the cookie.

### 3a. The "You" panel (profile)

Decided 2026-10-06. No separate profile menu; the Appearance panel under
Settings becomes a "You" panel with three rows: name, email, theme.

- **Name** is one field, not first and last. It is what document history shows
  as who created, edited, voided or emailed something, and what the title bar
  shows. First-run setup asks for it.
- **Email** is the login identifier in local mode, so changing it is a security
  action: a code goes to the new address and the change applies only when that
  code is confirmed. The old address is told.
- **Theme** stays as it is.
- **Launchpad mode:** name and email rows are read-only with a note that they
  come from Launchpad, which syncs them on every request; only the theme is
  editable here.

### 4. Launchpad mode

Exactly today's behaviour. Setup and People pages are not available, since the
hub owns who gets in. Sign out keeps pointing at the hub.

### 5. Mail

A login mailer with text and HTML versions of the code email and the welcome
email. Dev previews through letter_opener as now; production uses the MailerSend
settings already in place. The mailer host becomes configuration.

### 6. Security details that matter

- Codes hashed with the app secret, compared in constant time, expired and
  consumed on use.
- Throttling: at most a few code emails per address per quarter hour, and
  attempt limits per code. Done in the database, no new gem.
- `reset_session` before setting the user on sign-in, so the cookie rotates;
  ending other sessions is a later addition.
- No email enumeration, CSRF on every form, and the setup page unreachable once
  a user exists.

### 7. Tests

- Strategy chosen from configuration, both directions.
- The whole magic-code path: request, email sent, wrong code, expired code, too
  many attempts, success, sign out.
- Setup only before the first user; refused afterwards.
- Invites create a user and send the welcome email.
- Every existing Launchpad test keeps passing untouched, which is the proof
  Joel's path is unaffected.

### 8. Documentation

README gets a setup section for self-hosters: run migrations, visit the site,
create the first account, add Xero and SimpleFIN under Settings. DEPLOY.md and
CLAUDE.md describe both modes. The Launchpad section is marked as the optional
hub.

### 9. Sequence of commits

1. Move the domain and hub settings into credentials with current values as
   defaults, so production is unaffected.
2. Login code columns on users and the user model changes (bcrypt digest,
   expiry, attempts, sent-at; Launchpad id optional; email unique).
3. Local sign-in: controller, mailer, views, tests.
4. First-run setup.
5. Strategy switch in the base controller, sign-out and title bar reading from
   the active mode.
6. People page.
7. The "You" panel: name and theme editable, email change by confirmation
   code; read-only name and email in Launchpad mode.
8. Docs.

### Conventions carried over from rails-now

Joel's bootstrapper (`~/Work/rails-now/rails-now.sh`) generates the magic-code
login his other apps use. This app follows it so the shape is familiar:

- **Code issuing.** `issue_login_code!` makes a six-digit code with
  `format("%06d", SecureRandom.random_number(1_000_000))`, stores a bcrypt
  digest and an expiry (`CODE_TTL = 10.minutes`), and returns the plaintext for
  the mailer. `login_code_valid?(submitted)` checks presence, expiry, then
  `BCrypt::Password.new(digest) == submitted.to_s`. `clear_login_code!` wipes
  both columns after use. The `bcrypt` gem is already in the Gemfile.
- **Email normalisation.** `normalizes :email, with: ->(e) { e.strip.downcase }`
  and a case-insensitive uniqueness validation; fixtures carry distinct emails.
- **Mailer.** `LoginMailer.code(user, code)`, subject `"Your login code: 123456"`,
  HTML and text views, body says it expires in 10 minutes and to ignore it if
  not requested. Dev previews through letter_opener. A mailer preview and a
  mailer test calling the real signature.
- **Authentication concern.** `before_action :require_login`;
  `current_user` memoised into `Current.user` from `session[:user_id]`;
  `logged_in?`; `sign_in(user)` does `reset_session` then sets the id;
  `sign_out` does `reset_session`; `allow_unauthenticated` for the few open
  actions. `helper_method :current_user, :logged_in?`.
- **Sessions controller and routes.** `SessionsController` with
  `new` (email form), `create` (issue and email the code, redirect to verify),
  `verify` (code form), `confirm` (check, sign in, redirect to root),
  `destroy`; `skip_before_action :require_login, only: %i[new create verify confirm]`;
  routes `resource :session, only: %i[new create destroy] do get :verify; post :confirm end`.
- **Views.** Email field with `required` and `autofocus`; code field with
  `inputmode: "numeric"`, `pattern: "[0-9]*"`, `maxlength: 6`. The sign-out
  button is `button_to "Sign out", session_path, method: :delete`.
- **CLAUDE.md** describes the flow in one paragraph, as rails-now's generated
  file does.

Where this app deliberately differs, and why:

- **No Identity/User split.** rails-now keeps the credential on `Identity` and
  the tenant-scoped person on `User`. Here `users` already carries
  `email_address`, `name`, `theme` and the Launchpad id, and Launchpad sync
  writes to it; the split's purpose (one credential across tenants) is not
  needed while the app is single-tenant. The code columns go on `users`. If
  multi-tenant membership ever arrives, the split can be introduced then.
- **No open sign-up.** rails-now's `create` does `find_or_create_by(email)`, so
  any address gets an account on first login. A books app on the internet
  cannot do that: codes go only to existing users, the first user comes from
  the first-run setup page, and later users from the People page. The email
  form responds the same whether or not the address exists.
- **Limits rails-now does not have.** Five attempts per code, a few sends per
  address per quarter hour, both tracked on the user row.
- **Verify by signed token, not id.** rails-now passes `identity_id` in the
  URL; here the verify page is addressed by a short-lived signed token for the
  email, so user ids are not exposed and the one-click link in the email works
  the same way.
- **Launchpad stays a second strategy** behind the same concern, chosen by the
  presence of the `launchpad` credentials block.

### 10. Out of scope for this pass

Passwords, OAuth, two-factor, roles beyond a flat set of users, and
multi-tenant. The structure leaves room for all of them.

### Size

About a day with tests; roughly 28 files (about 16 new: 1 migration, an auth
strategy object, 3 controllers, 1 concern, 1 mailer with 4 templates plus a
preview, 4 views, an example credentials file; about 12 changed: base
controller, Launchpad concern, layout, routes, two environment files, user
model, test helper, 3 or 4 test files, README, DEPLOY.md, CLAUDE.md). Nothing in
documents, reconcile, reports or imports is touched.

## Rebrand: Ledger → Partita Doppia

Decided 2026-10-06. Not started. Do this before the Settings reorganisation;
both touch the layout and this one is smaller.

**The brand is the two words together, always.** "Partita Doppia" wherever
prose allows a space; `PartitaDoppia` or `partita_doppia` where an identifier
cannot. Never "Partita" or "Doppia" alone, and no abbreviation such as "PD".

**Two meanings of "ledger", only one changes.** The brand appears in nine
places: page title and `application-name` meta, the title bar wordmark and its
v0.1 tag, the sidebar footer, the status bar, the PWA manifest name and short
name, the no-access page wordmark, the stylesheet header comment, and this
document's title. The accounting term (the `Ledger` posting service,
`ledger_legs`, `ledger_description`, the General Ledger report, `LEDGER_CLASS`,
"ledger balance" in the bank summary, comments; about 40 files) stays as it is.

1. **One source of truth.** `config.x.app_name = "Partita Doppia"` and an
   `app_name` helper; every literal above reads from it. No short form exists.
2. **Chrome.** Title bar wordmark PARTITA DOPPIA beside the existing mark;
   status bar "Partita Doppia v0.1". Check the phone width where the nav is a
   horizontal strip; drop the tagline sooner if it crowds.
3. **PWA manifest.** `name` and `short_name` both "Partita Doppia" (the
   home-screen label may clip on some launchers; that is preferable to a split
   name). Description built from the organisation name.
4. **No-access page.** Wordmark from the helper; the Launchpad copy reads
   "You don't have access to Partita Doppia".
5. **Mail.** Default from-name on the base mailer becomes the app name. Invoice
   emails keep signing off with the organisation's name.
6. **Logo.** The bracket-and-dot mark and favicon stay; nothing in them says
   Ledger.
7. **Docs.** CLAUDE.md, DEPLOY.md, this document, the README when it exists,
   the stylesheet comment.
8. **Test** that the layout and manifest render the configured name.

Deliberately left alone: the Rails module `Accounting` (renaming it changes the
session cookie name and signs everyone out; if renamed later it becomes
`PartitaDoppia`), the Launchpad app key `accounting` (must match the hub's
registry; rename as a coordinated pair if ever), the GitHub repo (rename to
`partita_doppia` at publish time; GitHub redirects) and the Hatchbox app name
(never user-visible).

Size: about ten files, under an hour, no migrations.
