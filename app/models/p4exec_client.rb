require 'net/http'
require 'uri'

# The one place that talks to the p4exec execution service — used by
# EvaluateSubmissionJob (real submissions) and TestRunsController
# (ephemeral test runs). Raises on anything but the expected 202.
module P4execClient
  Error = Class.new(StandardError)

  INTERNAL_TOKEN = ENV.fetch('P4EXEC_INTERNAL_TOKEN', 'p4exec-dev-token')

  module_function

  def service_url = ENV['P4EXEC_SERVICE_URL']
  def enabled?    = service_url.present?

  # Always built OUTSIDE any request context: a controller's own url
  # helper inherits the current request's port (443 behind nginx) and
  # silently drops the :3000 embedded in the host — sending callbacks to
  # nginx's port-80 catch-all, which 404s unknown Hosts. The route
  # helpers on Rails.application.routes have no request to inherit from,
  # so the host string is used verbatim.
  def callback_url
    Rails.application.routes.url_helpers.internal_exec_callback_url(
      host:     ENV.fetch('RAILS_CALLBACK_HOST', 'localhost:3000'),
      protocol: 'http'
    )
  end

  def execute(job_id:, callback_url:, code:, topology:)
    uri  = URI("#{service_url}/execute")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 5
    http.read_timeout = 10

    req = Net::HTTP::Post.new(uri.path, {
      'Content-Type'     => 'application/json',
      'X-Internal-Token' => INTERNAL_TOKEN
    })
    req.body = { job_id: job_id, callback_url: callback_url, code: code, topology: topology }.to_json

    resp = http.request(req)
    unless resp.code.to_i == 202
      raise Error, "Execution service returned HTTP #{resp.code}: #{resp.body}"
    end
  end
end
