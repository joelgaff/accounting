require "application_system_test_case"

# The theme toggle lives at the bottom of a long settings page. Switching it
# repaints in place; nothing may scroll the window frame out of view.
class ThemeSwitchTest < ApplicationSystemTestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    sign_in_as_launchpad_user(@org)
  end

  test "switching the theme repaints the page and keeps the frame where it was" do
    visit "/settings"
    page.execute_script("const m = document.querySelector('.app-main'); m.scrollTop = m.scrollHeight")   # down to the You panel, as a person would
    find("label.theme-option", text: "Light", visible: :all).click
    assert_equal "light", page.evaluate_script("document.documentElement.dataset.theme")
    assert_selector "label.theme-option.is-active", text: /light/i                                          # the panel came back from the server

    assert_equal 0, page.evaluate_script("document.querySelector('.app-shell').scrollTop"), "the frame must not scroll"
    assert_selector ".app-titlebar .tb-name", visible: true
    assert_selector "nav.app-nav a", text: "Dashboard", visible: true
    assert_operator page.evaluate_script("document.querySelector('.app-titlebar').getBoundingClientRect().top"), :>=, 0
    shoot("theme after switch")

    bg  = page.evaluate_script("getComputedStyle(document.body).backgroundColor")
    ink = page.evaluate_script("getComputedStyle(document.querySelector('.panel-title')).color")
    assert_not_equal bg, ink
    assert_equal "light", User.find_by!(email_address: "joel@example.com").theme
  end
end
