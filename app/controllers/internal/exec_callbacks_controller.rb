module Internal
  # Receives progress and done events from the p4exec execution service.
  # Every event is a JSON body posted to POST /internal/exec_callback.
  class ExecCallbacksController < BaseController
    def create
      event = JSON.parse(request.body.read)
      job_id = event["job_id"].to_s

      # Ephemeral test runs (p4test_<uuid>) have no Submission row — they
      # live in the cache and stream to their own channel. See TestRun.
      if job_id.start_with?("p4test_")
        handle_test_run(job_id.delete_prefix("p4test_"), event)
        return head :ok
      end

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
        traffic_metrics = build_traffic_metrics(event["traffic_results"])
        feedback = build_feedback(event["feedback"], event["error"], traffic_metrics)
        captures = event["packet_captures"]

        evaluation = nil
        if event["status"] == "completed" && submission.exercise.has_evaluation_criteria?
          evaluation = SubmissionEvaluator.new(
            criteria:            submission.exercise.parsed_evaluation_criteria,
            structured_captures: event["structured_captures"],
            traffic_metrics:     traffic_metrics
          ).evaluate
        end

        submission.update!(
          status:                     event["status"] == "completed" ? "completed" : "failed",
          feedback:                   feedback,
          packet_captures:            captures&.to_json,
          structured_packet_captures: event["structured_captures"]&.to_json,
          passed:                     evaluation&.passed,
          evaluation_result:          evaluation && evaluation.as_json.to_json
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

        # Inject BMv2 switch log (sits right below the captures)
        Turbo::StreamsChannel.broadcast_replace_to(
          stream,
          target: "bmv2-log-#{submission.id}",
          html: ApplicationController.render(
            partial: "submissions/bmv2_log",
            locals:  { submission: submission }
          )
        )

        # Inject automated evaluation result panel
        Turbo::StreamsChannel.broadcast_replace_to(
          stream,
          target: "evaluation-result-#{submission.id}",
          html: ApplicationController.render(
            partial: "submissions/evaluation_result",
            locals:  { submission: submission }
          )
        )
      end

      head :ok
    end

    private

    # Mirror of the submission "done" flow for ephemeral test runs: same
    # partials, same Turbo targets — but rendered from an unsaved
    # Submission (TestRun#to_submission, fake DOM id) and persisted only
    # to the cache with a TTL, never to the database.
    def handle_test_run(uuid, event)
      test_run = TestRun.find(uuid)
      return if test_run.nil?  # expired mid-run — nothing to update

      stream = test_run.stream_name

      case event["type"]
      when "progress"
        phase = ERB::Util.html_escape(event["phase"].to_s)
        line  = ERB::Util.html_escape(event["line"].to_s)
        Turbo::StreamsChannel.broadcast_append_to(
          stream,
          target: "exec-log-#{test_run.dom_id}",
          html:   "<span class=\"log-#{phase}\">[#{phase}] #{line}</span>\n"
        )

      when "done"
        traffic_metrics = build_traffic_metrics(event["traffic_results"])

        evaluation = nil
        if event["status"] == "completed" && test_run.exercise.has_evaluation_criteria?
          evaluation = SubmissionEvaluator.new(
            criteria:            test_run.exercise.parsed_evaluation_criteria,
            structured_captures: event["structured_captures"],
            traffic_metrics:     traffic_metrics
          ).evaluate
        end

        test_run.store_result!(
          status:              event["status"] == "completed" ? "completed" : "failed",
          feedback:            build_feedback(event["feedback"], event["error"], traffic_metrics),
          packet_captures:     event["packet_captures"],
          structured_captures: event["structured_captures"],
          evaluation:          evaluation
        )

        submission = test_run.to_submission
        replace = ->(target, partial) {
          Turbo::StreamsChannel.broadcast_replace_to(
            stream,
            target: target,
            html: ApplicationController.render(partial: partial, locals: { submission: submission })
          )
        }
        replace.call("submission-status-card-#{submission.id}", "submissions/status_card")
        Turbo::StreamsChannel.broadcast_remove_to(stream, target: "exec-live-log-#{submission.id}")
        replace.call("submission-feedback-#{submission.id}",   "submissions/feedback_sections")
        replace.call("packet-captures-#{submission.id}",       "submissions/packet_captures")
        replace.call("bmv2-log-#{submission.id}",              "submissions/bmv2_log")
        replace.call("evaluation-result-#{submission.id}",     "submissions/evaluation_result")

        Rails.logger.info("[p4test] #{uuid} finished — #{event['status']} (ephemeral, no record)")
      end
    end

    # One entry per traffic test, in run order (legacy traffic_test first,
    # then the generator mappings — same order p4exec ran them). `metrics`
    # is nil for non-iperf tests (ping) and for failed/timed-out runs.
    def build_traffic_metrics(traffic_results)
      Array(traffic_results).map do |r|
        {
          "label"   => r["label"],
          "from"    => r["from"],
          "to"      => r["to"],
          "metrics" => IperfReport.parse(r["output"])
        }
      end
    end

    def build_feedback(feedback, error, traffic_metrics = [])
      parts = []
      if feedback.is_a?(Hash)
        parts << section("Compilation",      feedback["compile"])
        parts << section("Forwarding rules", feedback["rules"])
        parts << section("Traffic test",     traffic_section(feedback["traffic"], traffic_metrics))
        parts << section("BMv2 switch log",  feedback["switch_log"])
      end
      parts << section("Error", error) if error.present?
      parts.compact.join("\n\n")
    end

    # The raw traffic log now contains iperf3 JSON documents for generator
    # flows — unreadable in the UI. When metrics were parsed, show one
    # summary line per flow instead; tests without metrics (ping and
    # friends) keep their raw output via the log fallback.
    def traffic_section(raw_log, traffic_metrics)
      with_metrics = traffic_metrics.select { |t| t["metrics"] }
      return raw_log if with_metrics.empty?

      lines = traffic_metrics.each_with_index.map do |t, i|
        if t["metrics"]
          "[#{i + 1}] #{t['label']}: #{IperfReport.summary(t['metrics'])}"
        else
          "[#{i + 1}] #{t['label']}: see log below"
        end
      end

      raw_without_json = raw_log.to_s.split("\n\n").reject { |chunk|
        chunk.include?('"start"') || chunk.lstrip.start_with?("{")
      }.join("\n\n")

      [lines.join("\n"), raw_without_json.presence].compact.join("\n\n")
    end

    def section(title, body)
      return nil if body.blank?
      "── #{title} ──\n\n#{body}"
    end
  end
end
