require 'net/http'
require 'uri'
require 'json'

# Console-only channel: the user types a move, we run it against p4exec
# synchronously, and broadcast the reply back. Packet-panel and status
# updates use Turbo::StreamsChannel instead (see
# Internal::GameSessionCallbacksController) since those only ever flow
# server -> client, which Turbo Streams already handles.
class GameSessionChannel < ApplicationCable::Channel
  EXEC_INTERNAL_TOKEN = ENV.fetch('P4EXEC_INTERNAL_TOKEN', 'p4exec-dev-token')
  COMMAND_TIMEOUT = 5

  def subscribed
    game_session = GameSession.find_by(id: params[:id])
    if game_session.nil? || game_session.user != current_user
      reject
      return
    end

    stream_for game_session
  end

  def receive(data)
    game_session = GameSession.find_by(id: params[:id])
    return if game_session.nil? || game_session.user != current_user
    return unless game_session.status == 'active'

    host = data['host'].to_s
    return unless GameSession::HOSTS.include?(host)

    game_session.touch_activity!
    output = run_command(game_session, host, data['command'].to_s)

    GameSessionChannel.broadcast_to(game_session, {
      type:    'console_reply',
      host:    host,
      output:  output
    })
  end

  private

  def run_command(game_session, host, command)
    exec_service_url = ENV['P4EXEC_SERVICE_URL']
    return 'Sandbox error: P4EXEC_SERVICE_URL is not configured' unless exec_service_url.present?

    uri  = URI("#{exec_service_url}/session/#{game_session.p4exec_session_id}/command")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 3
    http.read_timeout = COMMAND_TIMEOUT

    req = Net::HTTP::Post.new(uri.path, {
      'Content-Type'     => 'application/json',
      'X-Internal-Token' => EXEC_INTERNAL_TOKEN
    })
    req.body = { host: host, args: command }.to_json

    resp = http.request(req)
    unless resp.code.to_i == 200
      return "Sandbox error: execution service returned HTTP #{resp.code}"
    end

    JSON.parse(resp.body)['output'].to_s
  rescue Net::OpenTimeout, Net::ReadTimeout
    'Sandbox error: no response from switch (timed out)'
  rescue => e
    "Sandbox error: #{e.message}"
  end
end
