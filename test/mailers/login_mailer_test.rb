require "test_helper"

class LoginMailerTest < ActionMailer::TestCase
  test "the code email carries the code, a prefilled link and the expiry" do
    user = organizations(:one).users.create!(email_address: "code@example.com", name: "Code")
    mail = LoginMailer.code(user, "123456")
    assert_equal [ "code@example.com" ], mail.to
    assert_equal "Your login code: 123456", mail.subject
    assert_match(/123456/, mail.text_part.body.to_s)
    assert_match(%r{/session/verify\?code=123456&(amp;)?token=\S+}, mail.html_part.body.to_s)
    assert_match(/10 minutes/, mail.text_part.body.to_s)
  end

  test "the welcome email names who added them and where to sign in" do
    org   = organizations(:one)
    joel  = org.users.create!(email_address: "joel@example.com", name: "Joel")
    newbie = org.users.create!(email_address: "new@example.com", name: "Newbie")
    mail = LoginMailer.welcome(newbie, added_by: joel)
    assert_match(/Joel added you/, mail.text_part.body.to_s)
    assert_match(%r{/session/new}, mail.text_part.body.to_s)
  end
end
