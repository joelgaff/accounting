require "test_helper"

class LoginMailerTest < ActionMailer::TestCase
  test "code" do
    identity = identities(:one)
    mail = LoginMailer.code(identity, "123456")
    assert_equal "Your login code: 123456", mail.subject
    assert_equal [identity.email], mail.to
    assert_match "123456", mail.body.encoded
  end
end
