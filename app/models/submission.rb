class Submission < ApplicationRecord
  belongs_to :user
  belongs_to :exercise

  validates :code, presence: true

  STATUSES = ['pending', 'completed', 'failed', 'evaluating']

  after_create :queue_evaluation

  private

  def queue_evaluation
    EvaluateSubmissionJob.perform_later(id)
  end
end
