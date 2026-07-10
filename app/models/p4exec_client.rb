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
