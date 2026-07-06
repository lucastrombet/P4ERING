class Submission < ApplicationRecord
  belongs_to :user
  belongs_to :exercise

  validates :code, presence: true

  STATUSES = ['pending', 'completed', 'failed', 'evaluating']

  def parsed_packet_captures
    JSON.parse(packet_captures) if packet_captures.present?
  rescue JSON::ParserError
    nil
  end

  # after_create_commit (not after_create) — EvaluateSubmissionJob queries this
  # row from a background thread, which can race the enclosing transaction's
  # commit under the :async adapter (development) and see nothing if this
  # fired inside it. Same fix as GameSession#after_create_commit.
  after_create_commit :queue_evaluation

  private

  def queue_evaluation
    EvaluateSubmissionJob.perform_later(id)
  end
end
