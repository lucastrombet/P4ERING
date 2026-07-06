require 'net/http'
require 'uri'
require 'json'

class StartGameSessionJob < ApplicationJob
  queue_as :default

  EXEC_INTERNAL_TOKEN = ENV.fetch('P4EXEC_INTERNAL_TOKEN', 'p4exec-dev-token')

  def exec_service_url = ENV['P4EXEC_SERVICE_URL']

  def perform(game_session_id)
    game_session = GameSession.find_by(id: game_session_id)
    return unless game_session

    unless exec_service_url.present?
      game_session.update!(status: 'failed', error: 'P4EXEC_SERVICE_URL is not configured')
      return
    end

    callback_url = Rails.application.routes.url_helpers
                        .internal_game_session_callback_url(
                          host:     ENV.fetch('RAILS_CALLBACK_HOST', 'localhost:3000'),
                          protocol: 'http'
                        )

    body = {
      session_id:   game_session.p4exec_session_id,
      callback_url: callback_url,
      topology:     GameSession::TOPOLOGY
    }.to_json

    uri  = URI("#{exec_service_url}/session/start")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 5
    http.read_timeout = 10

    req = Net::HTTP::Post.new(uri.path, {
      'Content-Type'     => 'application/json',
      'X-Internal-Token' => EXEC_INTERNAL_TOKEN
    })
    req.body = body

    resp = http.request(req)

    unless resp.code.to_i == 202
      game_session.update!(status: 'failed', error: "Execution service returned HTTP #{resp.code}: #{resp.body}")
      return
    end

    Rails.logger.info("[p4exec] Session #{game_session.p4exec_session_id} bring-up started")
    # Result arrives asynchronously via POST /internal/game_session_callback
  rescue => e
    game_session&.update(status: 'failed', error: "Sandbox error: #{e.message}")
  end
end
