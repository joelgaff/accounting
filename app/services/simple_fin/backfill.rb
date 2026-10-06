module SimpleFin
  # Pull history from a date in 90-day windows, recording each window on the
  # feed as it lands. SimpleFIN allows about 24 requests a day, so a run stops
  # after MAX_WINDOWS and says where to resume.
  class Backfill
    MAX_WINDOWS = 20
    Window = Struct.new(:from, :to, :imported, :duplicates, :errors, keyword_init: true)

    def initialize(feed, from:, client: feed.client)
      @feed, @from, @client = feed, from, client
    end

    def call
      @feed.update!(backfill_from: @from, backfill_started_at: Time.current, backfill_finished_at: nil, backfill_summary: { "windows" => [] }.to_json, last_error: nil)
      step    = Client::MAX_RANGE_DAYS - 1
      windows = []
      cursor  = @from
      while cursor <= Date.current && windows.size < MAX_WINDOWS
        finish  = [ cursor + step, Date.current ].min
        summary = Sync.new(@feed, client: @client, from: cursor, to: finish).call
        windows << Window.new(from: cursor, to: finish, imported: summary.imported, duplicates: summary.duplicates, errors: summary.errors.to_a)
        record!(windows, resume: nil)
        cursor = finish + 1
      end
      resume = cursor <= Date.current ? cursor : nil
      record!(windows, resume: resume, finished: true)
      { windows: windows, resume: resume }
    rescue Error, SocketError, Timeout::Error, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError => e
      record!(windows || [], resume: cursor, finished: true, error: e.message)
      raise
    end

    private

    def record!(windows, resume:, finished: false, error: nil)
      summary = { "windows" => windows.map { |w| w.to_h.transform_values { |v| v.is_a?(Date) ? v.iso8601 : v } },
                  "imported" => windows.sum(&:imported), "resume" => resume&.iso8601, "error" => error }
      @feed.update!(backfill_summary: summary.to_json, backfill_finished_at: (Time.current if finished))
    end
  end
end
