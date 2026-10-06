# Preview at http://accounting.lvh.me:3001/rails/mailers/login_mailer
class LoginMailerPreview < ActionMailer::Preview
  def code
    LoginMailer.code(User.first || User.new(email_address: "preview@example.com", name: "Preview"), "123456")
  end

  def welcome
    LoginMailer.welcome(User.first || User.new(email_address: "preview@example.com", name: "Preview", organization: Organization.first), added_by: User.first || User.new(name: "Joel"))
  end
end
