require "test_helper"

class XeroConnectionPagesTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
  end

  test "explains the setup when no app credentials are configured" do
    stub_method(Xero::Client, :configured?, -> { false }) do
      get xero_connection_path
      assert_response :success
      assert_select "code", text: /xero.client_id/
      assert_select "button[disabled]", text: "Connect to Xero"
      assert_select "form[data-turbo=false] button", text: "Connect to Xero", count: 1
    end
  end

  test "connects via oauth, starts an import in the background, and disconnects" do
    fake = FakeXero.new
    stub_method(Xero::Client, :exchange_code, ->(code, redirect_uri:, transport: nil) { Xero::Client.send(:token_request, { grant_type: "authorization_code", code: code, redirect_uri: redirect_uri }, fake) }) do
      stub_method(Xero::Client, :connections, ->(token, transport: nil) { fake.call(Net::HTTP::Get.new(URI(Xero::Client::CONNECTIONS)), URI(Xero::Client::CONNECTIONS)).then { |r| JSON.parse(r.body) } }) do
        post connect_xero_connection_path
        assert_response :redirect
        state = response.location[/state=(\w+)/, 1]
        assert_match(/login\.xero\.com/, response.location)

        get callback_xero_connection_path(code: "the-code", state: "wrong")
        assert_redirected_to xero_connection_path
        assert_nil @org.reload.xero_connection

        post connect_xero_connection_path
        state = response.location[/state=(\w+)/, 1]
        get callback_xero_connection_path(code: "the-code", state: state)
        assert_redirected_to xero_connection_path
        conn = @org.reload.xero_connection
        assert_equal "tenant-1", conn.tenant_id
        assert_equal "Endurance Evolution, LLC", conn.tenant_name
      end
    end

    get xero_connection_path
    assert_select "strong", text: "Endurance Evolution, LLC"

    assert_enqueued_with(job: XeroImportJob) do
      patch xero_connection_path, params: { import_from: "2019-01-01" }
    end
    assert_equal "running", @org.xero_connection.reload.status
    assert_equal Date.new(2019, 1, 1), @org.xero_connection.import_from
    get xero_connection_path
    assert_select "turbo-frame[id=?][src=?]", "progress_xero_connection_#{@org.xero_connection.id}", progress_xero_connection_path
    assert_select "[data-controller=poll][data-poll-active-value=true]"
    assert_select "pre.tui-progress", text: /0\/11/

    @org.xero_connection.record_step!("chart of accounts", Imports::BaseService::Result.new(created: 5))
    @org.xero_connection.record_step!("tax rates")
    get progress_xero_connection_path
    assert_response :success
    assert_select "turbo-frame[id=?]", "progress_xero_connection_#{@org.xero_connection.id}"
    assert_select "pre.tui-progress", text: /▓░{10} 1\/11  tax rates/

    @org.xero_connection.update!(status: "done", last_import_at: Time.current)
    get xero_connection_path
    assert_select "[data-controller=poll][data-poll-active-value=false]"
    assert_select "pre.tui-progress", count: 0
    @org.xero_connection.update!(status: "running")

    patch xero_connection_path
    assert_redirected_to xero_connection_path
    assert_match(/already running/, flash[:alert])

    delete xero_connection_path
    assert_nil @org.reload.xero_connection
  end
end
