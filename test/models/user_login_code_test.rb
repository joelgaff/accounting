require "test_helper"

class UserLoginCodeTest < ActiveSupport::TestCase
  setup do
    @org  = organizations(:one)
    @user = @org.users.create!(email_address: "  Joel@Example.com ", name: "Joel")
  end

  test "email is normalised and unique among local users, while hub users may repeat" do
    assert_equal "joel@example.com", @user.email_address
    dup = @org.users.build(email_address: "JOEL@example.com", name: "Again")
    assert_not dup.valid?
    assert @org.users.build(email_address: "joel@example.com", name: "Hub", launchpad_public_id: "u-x").valid?
  end

  test "a code is six digits, stored hashed, checked once, and voided after five wrong guesses" do
    code = @user.issue_login_code!
    assert_match(/\A\d{6}\z/, code)
    assert_not_equal code, @user.login_code_digest
    assert_not @user.login_code_valid?("000000")
    assert_equal 1, @user.reload.login_code_attempts
    assert @user.login_code_valid?(" #{code} ")
    @user.clear_login_code!
    assert_not @user.login_code_valid?(code), "single use"

    code = @user.issue_login_code!
    5.times { @user.login_code_valid?("999999") }
    assert_not @user.login_code_valid?(code), "too many guesses voids the code"
  end

  test "an expired code fails" do
    code = @user.issue_login_code!
    @user.update!(login_code_expires_at: 1.minute.ago)
    assert_not @user.login_code_valid?(code)
  end

  test "three sends in a quarter hour is the limit" do
    3.times { @user.issue_login_code! }
    assert @user.login_code_throttled?
    assert_raises(User::TooManyRequests) { @user.issue_login_code! }
    @user.update!(login_code_sent_at: 20.minutes.ago)
    assert_not @user.login_code_throttled?
    @user.issue_login_code!
    assert_equal 1, @user.login_code_sends, "the window restarted"
  end
end
