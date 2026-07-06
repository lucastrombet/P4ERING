# Backstop for the common "user just closed the tab" case: p4exec has its
# own in-process idle reaper, but Rails has no way to know a session went
# idle unless something checks — GameSessionChannel#receive only bumps
# last_seen_at while the user is actively typing, it never notices when they
# stop. This job is the one that actually catches that and reflects it in
# the database (p4exec's reaper only tears down containers on its side).
class ReapGameSessionsJob < ApplicationJob
  queue_as :background

  IDLE_TIMEOUT = 15.minutes

  def perform
    GameSession.active.where('last_seen_at < ? OR (last_seen_at IS NULL AND started_at < ?)',
                              IDLE_TIMEOUT.ago, IDLE_TIMEOUT.ago).find_each do |game_session|
      game_session.end_on_exec_service!
      game_session.update(status: 'expired', ended_at: Time.current)
    end
  end
end
