class AdminController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin
  
  def dashboard
    @users = User.all
    @exercises = Exercise.all
    @submissions = Submission.includes(:user, :exercise).order(created_at: :desc).limit(10)
    @total_submissions = Submission.count
    @completed_submissions = Submission.where(status: 'completed').count
  end
  
  private
  
  def require_admin
    unless current_user.admin?
      redirect_to root_path, alert: "Access denied. Admin privileges required."
    end
  end
end
