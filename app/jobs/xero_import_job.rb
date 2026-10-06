# Runs the Xero API import in the background; progress lands on the connection.
class XeroImportJob < ApplicationJob
  queue_as :default

  def perform(connection_id)
    connection = XeroConnection.find(connection_id)
    Xero::Import.new(connection).call
  rescue Xero::Error, SocketError, Timeout::Error, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError => e
    Rails.logger.error("[XeroImportJob] connection #{connection_id}: #{e.class}: #{e.message}")   # status already says failed
  end
end
