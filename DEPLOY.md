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

Operators keep their own notes, scripts and checklists outside this repository
(the maintainer's live in a private companion repo cloned beside this one).
