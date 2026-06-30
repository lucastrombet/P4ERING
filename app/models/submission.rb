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

  after_create :queue_evaluation

  private

  def queue_evaluation
    EvaluateSubmissionJob.perform_later(id)
  end
end
