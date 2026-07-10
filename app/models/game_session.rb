require 'net/http'
require 'uri'

class GameSession < ApplicationRecord
  belongs_to :user

  STATUSES = %w[pending active ended failed expired].freeze
  HOSTS = %w[h1 h2].freeze

  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: %w[pending active]) }

  # Fixed 2-host + 1-switch topology for the P4CHECKERS sandbox. There is
  # exactly one topology for this feature, so unlike Exercise#topology_config
  # this isn't admin-editable JSON — just a constant reusing the same shape.
  TOPOLOGY = {
    switch: { name: 'sw1', thrift_port: 50001, image: 'ghcr.io/lucastrombet/p4ering/p4d:1.0' },
    connections: [
      { port: 1, host_name: 'h1', host_image: 'ghcr.io/lucastrombet/p4ering/net:1.0',
        host_ip: '10.0.1.1/24', host_mac: '08:00:00:01:01:01',
        sw_ip: '10.0.1.254/24', sw_mac: '08:00:00:01:00:01' },
      { port: 2, host_name: 'h2', host_image: 'ghcr.io/lucastrombet/p4ering/net:1.0',
        host_ip: '10.0.1.2/24', host_mac: '08:00:00:01:01:02',
        sw_ip: '10.0.1.253/24', sw_mac: '08:00:00:01:00:02' }
    ]
  }.freeze

  # after_create_commit (not after_create) — StartGameSessionJob queries this
  # row from a background thread (the :async adapter in development runs jobs
  # almost immediately), which would race the enclosing transaction's commit
  # and see nothing if this fired inside it.
  after_create_commit :queue_start

  def p4exec_session_id = "gs_#{id}"

  def touch_activity!
    update_column(:last_seen_at, Time.current)
  end

  # Best-effort — tells p4exec to tear down the containers. Safe to call even
  # if the session is already gone on the p4exec side (a 404 is ignored).
  def end_on_exec_service!
    exec_service_url = ENV['P4EXEC_SERVICE_URL']
    return unless exec_service_url.present?

    uri  = URI("#{exec_service_url}/session/#{p4exec_session_id}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 3
    http.read_timeout = 5

    req = Net::HTTP::Delete.new(uri.path, {
      'X-Internal-Token' => ENV.fetch('P4EXEC_INTERNAL_TOKEN', 'p4exec-dev-token')
    })
    http.request(req)
  rescue => e
    Rails.logger.warn("[p4exec] failed to end session #{p4exec_session_id}: #{e.message}")
  end

  private

  def queue_start
    update_column(:started_at, Time.current)
    StartGameSessionJob.perform_later(id)
  end
end
