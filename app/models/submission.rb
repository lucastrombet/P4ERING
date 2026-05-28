class Submission < ApplicationRecord
  belongs_to :user
  belongs_to :exercise

  validates :code, presence: true

  STATUSES = ['pending', 'completed', 'failed', 'evaluating']

  after_create :queue_evaluation

  private

  def queue_evaluation
    # In production, this would queue a background job
    # For demo, we'll just evaluate synchronously
    evaluate_code
  end

  def evaluate_code
    update(status: 'evaluating')

    # Simulate code evaluation
    # In a real app, you'd run the code in a sandbox environment
    if code.present? && code.length > 10
      update(
        status: 'completed',
        feedback: "Code submitted successfully! Your solution has been recorded."
      )
    else
      update(
        status: 'failed',
        feedback: "Code is too short. Please provide a complete solution."
      )
    end
  end
end
