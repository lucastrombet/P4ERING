module Internal
  # Receives progress and done events from the p4exec execution service.
  # Every event is a JSON body posted to POST /internal/exec_callback.
  class ExecCallbacksController < ApplicationController
    skip_before_action :verify_authenticity_token
    skip_before_action :authenticate_user!   if method_defined?(:authenticate_user!)
    before_action :verify_internal_token

    def create
      event = JSON.parse(request.body.read)
      job_id = event["job_id"].to_s
      submission_id = job_id.delete_prefix("p4t_").to_i
      submission = Submission.find_by(id: submission_id)

      unless submission
        render json: { error: "submission not found" }, status: :not_found and return
      end

      stream = "submission_#{submission.id}"

      case event["type"]
      when "progress"
        Rails.logger.info("[p4exec] #{job_id} [#{event['phase']}] #{event['line']}")
        phase = ERB::Util.html_escape(event["phase"].to_s)
        line  = ERB::Util.html_escape(event["line"].to_s)
        Turbo::StreamsChannel.broadcast_append_to(
          stream,
          target: "exec-log-#{submission.id}",
          html:   "<span class=\"log-#{phase}\">[#{phase}] #{line}</span>\n"
        )

      when "done"
        feedback = build_feedback(event["feedback"], event["error"])
        captures = event["packet_captures"]
        submission.update!(
          status:          event["status"] == "completed" ? "completed" : "failed",
          feedback:        feedback,
          packet_captures: captures&.to_json
        )
        Rails.logger.info("[p4exec] #{job_id} finished — #{event['status']}")

        # Replace status badge
        Turbo::StreamsChannel.broadcast_replace_to(
          stream,
          target: "submission-status-card-#{submission.id}",
          html: ApplicationController.render(
            partial: "submissions/status_card",
            locals:  { submission: submission }
          )
        )

        # Remove live log panel
        Turbo::StreamsChannel.broadcast_remove_to(
          stream,
          target: "exec-live-log-#{submission.id}"
        )

        # Inject feedback sections
        Turbo::StreamsChannel.broadcast_replace_to(
          stream,
          target: "submission-feedback-#{submission.id}",
          html: ApplicationController.render(
            partial: "submissions/feedback_sections",
            locals:  { submission: submission }
          )
        )

        # Inject packet capture panel
        Turbo::StreamsChannel.broadcast_replace_to(
          stream,
          target: "packet-captures-#{submission.id}",
          html: ApplicationController.render(
            partial: "submissions/packet_captures",
            locals:  { submission: submission }
          )
        )
      end

      head :ok
    end

    private

    def verify_internal_token
      expected = ENV.fetch("P4EXEC_INTERNAL_TOKEN", "p4exec-dev-token")
      given    = request.headers["X-Internal-Token"]
      head :unauthorized unless given == expected
    end

    def build_feedback(feedback, error)
      parts = []
      if feedback.is_a?(Hash)
        parts << section("Compilation",      feedback["compile"])
        parts << section("Forwarding rules", feedback["rules"])
        parts << section("Traffic test",     feedback["traffic"])
        parts << section("BMv2 switch log",  feedback["switch_log"])
      end
      parts << section("Error", error) if error.present?
      parts.compact.join("\n\n")
    end

    def section(title, body)
      return nil if body.blank?
      "── #{title} ──\n\n#{body}"
    end
  end
end
