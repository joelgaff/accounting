# Run using bin/ci

CI.run do
  step "Setup", "bin/setup --skip-server"

  step "Style: Ruby", "bin/rubocop"

  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Importmap vulnerability audit", "bin/importmap audit"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
  step "Tests: Rails", "bin/rails test"
  step "Tests: Seeds", "env RAILS_ENV=test bin/rails db:seed:replant"

  # Browser tests: every page at phone width, the More sheet, cards, action
  # bars. Headless Chromium; about four minutes. After the unit suite, so a
  # unit failure stops things before the slow part.
  step "Tests: Phone and browser", "bin/rails test:system"

  # Signoff (the green GitHub status) happens in .githooks/pre-push, once the
  # commit is on GitHub.
end
