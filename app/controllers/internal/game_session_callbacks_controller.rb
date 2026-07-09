module Internal
  # Receives session_ready/session_error/packet_batch/session_ended events
  # from p4exec for interactive GameSession sandboxes. Sibling to
  # ExecCallbacksController (which is hard-keyed to Submission lookups) —
  # kept separate rather than branching one controller on job vs session ids.
  class GameSessionCallbacksController < BaseController
    def create
      event = JSON.parse(request.body.read)
      session_id = event["session_id"].to_s
      game_session_id = session_id.delete_prefix("gs_").to_i
      game_session = GameSession.find_by(id: game_session_id)

      unless game_session
        render json: { error: "game session not found" }, status: :not_found and return
      end

      stream = "game_session_#{game_session.id}"

      case event["type"]
      when "session_ready"
        game_session.update!(status: "active")
        Rails.logger.info("[p4exec] #{session_id} ready")
        Turbo::StreamsChannel.broadcast_replace_to(
          stream,
          target: "game-session-status-#{game_session.id}",
          html: ApplicationController.render(
            partial: "game_sessions/status_card",
            locals:  { game_session: game_session }
          )
        )

      when "session_error"
        game_session.update!(status: "failed", error: event["error"])
        Rails.logger.warn("[p4exec] #{session_id} failed to start: #{event['error']}")
        Turbo::StreamsChannel.broadcast_replace_to(
          stream,
          target: "game-session-status-#{game_session.id}",
          html: ApplicationController.render(
            partial: "game_sessions/status_card",
            locals:  { game_session: game_session }
          )
        )

      when "packet_batch"
        host = event["host"].to_s
        lines = Array(event["lines"])

        if lines.any?
          # Absolute timestamps, not relative-to-first-packet-in-this-batch —
          # each batch is parsed independently in its own stateless request,
          # so "time since first packet" would restart at zero every batch.
          packets = ApplicationController.helpers.parse_tcpdump_output(lines.join("\n"), base_ts: false)

          # Full header decodes, index-aligned with `lines` (both views of
          # the same in-container pcap file — see game_session_executor.py).
          # Paired via pkt[:no] the same way the submissions view pairs
          # structured captures, and before filtering so indexes still match.
          structured = Array(event["packets"])
          pairs = packets.map { |pkt| [pkt, structured[pkt[:no] - 1]] }

          # The pseudo-Wireshark panels are meant to illustrate the game's
          # own traffic — filter out ARP and IPv6 (router solicitation, etc.)
          # noise from the containers' network stacks so only IPv4 shows.
          pairs = pairs.select { |pkt, _| %w[ICMP UDP TCP IPv4].include?(pkt[:proto]) }

          if pairs.any?
            Turbo::StreamsChannel.broadcast_append_to(
              stream,
              target: "packet-table-#{host}-body",
              partial: "game_sessions/packet_rows",
              locals:  { packet_pairs: pairs, host: host }
            )
          end
        end

      when "console_push"
        # A successful move gets forwarded straight to the opponent's port
        # instead of replying to the mover (see ForwardToOpponent in
        # checkers.p4) — p4exec sniffs that forwarded packet off the wire
        # and hands us its payload here so the opponent's console updates
        # without them having to manually re-query the board. Reuses the
        # exact same 'console_reply' message the JS already knows how to
        # append (GameSessionChannel#receive sends the same shape for a
        # host's own command replies).
        host = event["host"].to_s
        output = event["output"].to_s
        if output.present?
          GameSessionChannel.broadcast_to(game_session, {
            type:   "console_reply",
            host:   host,
            output: output
          })
        end

      when "session_ended"
        game_session.update!(status: "ended", ended_at: Time.current)
        Rails.logger.info("[p4exec] #{session_id} ended (#{event['reason']})")
        Turbo::StreamsChannel.broadcast_replace_to(
          stream,
          target: "game-session-status-#{game_session.id}",
          html: ApplicationController.render(
            partial: "game_sessions/status_card",
            locals:  { game_session: game_session }
          )
        )
      end

      head :ok
    end
  end
end
