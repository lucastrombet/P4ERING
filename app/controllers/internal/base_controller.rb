module Internal
  # Shared base for controllers receiving callbacks from the p4exec
  # execution service — CSRF/session auth don't apply to a server-to-server
  # callback, so both skip them and instead require a matching internal token.
  class BaseController < ApplicationController
    skip_before_action :verify_authenticity_token
    skip_before_action :authenticate_user!   if method_defined?(:authenticate_user!)
    before_action :verify_internal_token

    private

    def verify_internal_token
      expected = ENV.fetch("P4EXEC_INTERNAL_TOKEN", "p4exec-dev-token")
      given    = request.headers["X-Internal-Token"]
      head :unauthorized unless given == expected
    end
  end
end
