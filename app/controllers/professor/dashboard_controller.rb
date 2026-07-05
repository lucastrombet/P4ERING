class Professor::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :require_professor

  def index
    @exercises   = Exercise.all
    @submissions = Submission.includes(:user, :exercise).order(created_at: :desc).limit(10)
    @total_submissions     = Submission.count
    @completed_submissions = Submission.where(status: 'completed').count
    @pending_submissions   = Submission.where(status: %w[pending evaluating]).count
  end

  private

  def require_professor
    unless current_user.staff?
      redirect_to root_path, alert: 'Access denied.'
    end
  end
end
