# Settings → Xero: connect this organisation to its Xero organisation over
# OAuth, run the migration from the API, watch it, disconnect.
class XeroConnectionsController < ApplicationController
  before_action :load_connection, only: %i[show update destroy]

  def show
    @configured = Xero::Client.configured?
  end

  # Off to Xero's consent screen.
  def connect
    return redirect_to xero_connection_path, alert: "Add xero.client_id and xero.client_secret to the credentials first." unless Xero::Client.configured?
    session[:xero_state] = SecureRandom.hex(16)
    redirect_to Xero::Client.authorize_url(redirect_uri: callback_xero_connection_url, state: session[:xero_state]), allow_other_host: true
  end

  # Back from Xero with a code: swap it for tokens and pick the organisation.
  def callback
    if params[:error].present? || params[:state].blank? || params[:state] != session.delete(:xero_state)
      return redirect_to xero_connection_path, alert: "Xero didn't authorise the connection (#{params[:error].presence || 'state mismatch'})."
    end
    tokens  = Xero::Client.exchange_code(params.require(:code), redirect_uri: callback_xero_connection_url)
    tenants = Xero::Client.connections(tokens[:access_token])
    tenant  = tenants.find { |t| t["tenantType"] == "ORGANISATION" } || tenants.first
    return redirect_to xero_connection_path, alert: "That Xero login has no organisation to connect." if tenant.nil?

    connection = Current.organization.xero_connection || Current.organization.build_xero_connection
    connection.update!(tenant_id: tenant["tenantId"], tenant_name: tenant["tenantName"], access_token: tokens[:access_token],
                       refresh_token: tokens[:refresh_token], token_expires_at: tokens[:expires_at], status: "idle")
    redirect_to xero_connection_path, notice: "Connected to #{tenant['tenantName']}."
  rescue Xero::Error => e
    redirect_to xero_connection_path, alert: e.message
  end

  # Start (or restart) the import from the date given.
  def update
    return redirect_to xero_connection_path, alert: "An import is already running." if @connection.running?
    from = params[:import_from].present? ? Date.parse(params[:import_from]) : nil
    @connection.update!(import_from: from, status: "running", started_at: Time.current, progress: "[]", last_error: nil)
    XeroImportJob.perform_later(@connection.id)
    redirect_to xero_connection_path, notice: "Import started. This page refreshes while it runs."
  rescue ArgumentError
    redirect_to xero_connection_path, alert: "That start date isn't a date."
  end

  def destroy
    @connection.destroy
    redirect_to xero_connection_path, notice: "Disconnected from Xero. Everything already imported stays."
  end

  private

  def load_connection
    @connection = Current.organization.xero_connection
    redirect_to xero_connection_path, alert: "Xero isn't connected yet." if @connection.nil? && action_name != "show"
  end
end
