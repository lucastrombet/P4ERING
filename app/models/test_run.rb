# An ephemeral "Testar Código" run — deliberately NOT a Submission and NOT
# a database row. Lives entirely in the cache (solid_cache) under a random
# UUID with a short TTL, then evaporates: no id is consumed, the
# submissions table stays clean, and nothing needs purging.
#
# The submission page partials (_status_card, _packet_captures, _bmv2_log,
# _feedback_sections, _evaluation_result) all key their DOM ids off
# `submission.id`. Rather than parameterizing every partial, #to_submission
# builds an UNSAVED Submission carrying a fake numeric id derived
# deterministically from the UUID — so the initial page render and the
# Turbo Stream broadcasts (both derived from the same UUID) always agree.
class TestRun
  TTL = 1.hour

  attr_reader :uuid, :meta, :result

  def self.create!(user:, exercise:, code:)
    uuid = SecureRandom.uuid
    meta = {
      'user_id'     => user.id,
      'exercise_id' => exercise.id,
      'code'        => code,
      'created_at'  => Time.current.iso8601,
    }
    Rails.cache.write(meta_key(uuid), meta, expires_in: TTL)
    new(uuid, meta, nil)
  end

  def self.find(uuid)
    meta = Rails.cache.read(meta_key(uuid))
    return nil unless meta

    new(uuid, meta, Rails.cache.read(result_key(uuid)))
  end

  def self.meta_key(uuid)   = "test_run:#{uuid}:meta"
  def self.result_key(uuid) = "test_run:#{uuid}:result"

  def initialize(uuid, meta, result)
    @uuid = uuid
    @meta = meta
    @result = result
  end

  def store_result!(status:, feedback:, packet_captures:, structured_captures:, evaluation:)
    @result = {
      'status'                     => status,
      'feedback'                   => feedback,
      'packet_captures'            => packet_captures&.to_json,
      'structured_packet_captures' => structured_captures&.to_json,
      'passed'                     => evaluation&.passed,
      'evaluation_result'          => evaluation && evaluation.as_json.to_json,
    }
    Rails.cache.write(self.class.result_key(uuid), @result, expires_in: TTL)
  end

  def user_id      = meta['user_id']
  def exercise     = @exercise ||= Exercise.find(meta['exercise_id'])
  def created_at   = Time.iso8601(meta['created_at'])
  def done?        = result.present?
  def stream_name  = "test_run_#{uuid}"

  def viewable_by?(user)
    user.id == user_id || user.admin?
  end

  # Stable pseudo-id for DOM targets — never collides with real submission
  # ids in practice (48 bits of the UUID, values far beyond any sequence),
  # and never persisted anywhere.
  def dom_id
    @dom_id ||= uuid.delete('-').first(12).to_i(16)
  end

  def to_submission
    s = Submission.new(
      exercise_id: meta['exercise_id'],
      user_id:     user_id,
      code:        meta['code'],
      test_run:    true,
      status:      result ? result['status'] : 'evaluating',
      created_at:  created_at
    )
    if result
      s.feedback                   = result['feedback']
      s.packet_captures            = result['packet_captures']
      s.structured_packet_captures = result['structured_packet_captures']
      s.passed                     = result['passed']
      s.evaluation_result          = result['evaluation_result']
    end
    s.id = dom_id
    s
  end
end
