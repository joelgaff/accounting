require "test_helper"

# The built-in magic-code sign-in, exercised end to end in local mode.
class LocalSignInTest < ActionDispatch::IntegrationTest
  setup    { ENV["AUTH_MODE"] = "local" }
  teardown { ENV.delete("AUTH_MODE") }

  def code_from_last_email
    ActionMailer::Base.deliveries.last.text_part.body.to_s[/login code is: (\d{6})/, 1]
  end

  test "first run sets up the books, then codes sign people in and out" do
    assert User.local.none?
    get root_path
    assert_redirected_to new_setup_path
    get new_setup_path
    assert_response :success
    assert_select "h1", text: "Set up your books"

    perform_enqueued_jobs do
      post setup_path, params: { organization_name: "Acme Timing", name: "Joel", email: "Joel@Example.com " }
    end
    assert_response :redirect
    assert_match %r{/session/verify\?token=}, response.location
    user = User.local.sole
    assert_equal "joel@example.com", user.email_address
    assert_equal "Acme Timing", user.organization.name
    assert_equal 1, ActionMailer::Base.deliveries.size
    assert_equal "Your login code: #{code_from_last_email}", ActionMailer::Base.deliveries.last.subject

    follow_redirect!
    assert_select "strong", text: "joel@example.com"
    token = response.request.params[:token]

    post confirm_session_path, params: { token: token, code: "000000" }
    assert_response :unprocessable_entity
    assert_select ".flash-alert", text: /isn't right/

    post confirm_session_path, params: { token: token, code: code_from_last_email }
    assert_redirected_to root_path
    get root_path
    assert_response :success
    assert_select ".tb-session span", text: "joel@example.com"
    assert_select "form[action=?] button", session_path, text: "Sign out"

    get new_setup_path
    assert_redirected_to new_session_path, "setup is gone once someone exists"

    delete session_path
    assert_redirected_to new_session_path
    get root_path
    assert_redirected_to new_session_path

    # Signing in again, and an address nobody has gets the same answer without an email.
    perform_enqueued_jobs do
      post session_path, params: { email: "joel@example.com" }
      assert_equal 2, ActionMailer::Base.deliveries.size
      post session_path, params: { email: "stranger@example.com" }
      assert_equal 2, ActionMailer::Base.deliveries.size
    end
    assert_response :redirect
    assert_match %r{/session/verify\?token=}, response.location

    get verify_session_path(token: "tampered")
    assert_redirected_to new_session_path

    mail = ActionMailer::Base.deliveries.last
    link = mail.text_part.body.to_s[%r{(http://\S+/session/verify\?\S+)}, 1]
    code = mail.subject[/\d{6}/]
    get link
    assert_response :success
    assert_select "input[name=code][value=?]", code, count: 1   # the email's link arrives with the code filled in
  end

  test "a used code cannot be replayed and five wrong guesses void one" do
    org  = organizations(:one)
    user = org.users.create!(email_address: "pat@example.com", name: "Pat")
    code = user.issue_login_code!
    token = Rails.application.message_verifier(:login).generate("pat@example.com", expires_in: 15.minutes)
    post confirm_session_path, params: { token: token, code: code }
    assert_redirected_to root_path
    delete session_path
    post confirm_session_path, params: { token: token, code: code }
    assert_response :unprocessable_entity

    code = user.issue_login_code!
    5.times { post confirm_session_path, params: { token: token, code: "111111" } }
    post confirm_session_path, params: { token: token, code: code }
    assert_response :unprocessable_entity, "voided after five wrong guesses"
  end

  test "in launchpad mode the sign-in pages hand over to the hub" do
    ENV.delete("AUTH_MODE")
    get new_session_path
    assert_response :redirect
    assert_match %r{launchpad\.example\.com/token}, response.location
    get new_setup_path
    assert_redirected_to new_session_path
  end
end

class PeopleAndProfileTest < ActionDispatch::IntegrationTest
  setup do
    ENV["AUTH_MODE"] = "local"
    @org  = organizations(:one)
    Organization.where.not(id: @org.id).destroy_all   # set_organization resolves Organization.first
    @joel = @org.users.create!(email_address: "joel@example.com", name: "Joel")
    code  = @joel.issue_login_code!
    post confirm_session_path, params: { token: Rails.application.message_verifier(:login).generate("joel@example.com", expires_in: 15.minutes), code: code }
  end
  teardown { ENV.delete("AUTH_MODE") }

  test "people can be added with a welcome email and removed, but not yourself" do
    get settings_path
    assert_select ".settings-row-action a[href=?]", people_path
    get people_path
    assert_select "td", text: /Joel/

    assert_enqueued_emails 1 do
      post people_path, params: { user: { name: "Pat", email_address: "Pat@Example.com" } }
    end
    assert_redirected_to people_path
    pat = @org.users.local.find_by!(email_address: "pat@example.com")

    post people_path, params: { user: { name: "Again", email_address: "pat@example.com" } }
    assert_response :unprocessable_entity

    delete person_path(@joel)
    assert_match(/can't remove yourself/, flash[:alert])
    delete person_path(pat)
    assert_nil User.find_by(id: pat.id)
  end

  test "you can rename yourself and change your email only by confirming a code sent to it" do
    patch profile_settings_path, params: { user: { name: "Joel G" } }
    assert_equal "Joel G", @joel.reload.name

    perform_enqueued_jobs do
      patch email_settings_path, params: { email: "new@example.com" }
    end
    assert_equal "new@example.com", @joel.reload.pending_email_address
    assert_equal "joel@example.com", @joel.email_address, "nothing changes until the code comes back"
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "new@example.com" ], mail.to
    code = mail.subject[/\d{6}/]

    get settings_path
    assert_select "input[name=code]"
    patch confirm_email_settings_path, params: { code: "000000" }
    assert_equal "joel@example.com", @joel.reload.email_address

    perform_enqueued_jobs do
      patch confirm_email_settings_path, params: { code: code }
    end
    assert_equal "new@example.com", @joel.reload.email_address
    assert_nil @joel.pending_email_address
    assert_equal [ "joel@example.com" ], ActionMailer::Base.deliveries.last.to, "the old address is told"

    patch email_settings_path, params: { email: "one@example.com" }
    assert_match(/already in use|already your/, flash[:alert].to_s + "x") if @org.users.local.where(email_address: "one@example.com").exists?
  end

  test "in launchpad mode the You panel is read-only and People points at the hub" do
    ENV.delete("AUTH_MODE")
    sign_in_as_launchpad_user(@org)
    get settings_path
    assert_select ".settings-row-main", text: /from Launchpad/
    assert_select "a", text: "Open Launchpad"
    get people_path
    assert_redirected_to settings_path
    patch profile_settings_path, params: { user: { name: "Nope" } }
    assert_redirected_to settings_path
  end
end
