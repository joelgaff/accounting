require "test_helper"

class LoginMailerTest < ActionMailer::TestCase
  test "code" do
    mail = LoginMailer.code
    assert_equal "Code", mail.subject
    assert_equal [ "to@example.org" ], mail.to
    assert_equal [ "from@example.com" ], mail.from
    assert_match "Hi", mail.body.encoded
  end
end
