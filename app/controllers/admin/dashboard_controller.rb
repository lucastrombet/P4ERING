# app/controllers/admin/dashboard_controller.rb
class Admin::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin
  
  def index
    @users = User.all
    @exercises = Exercise.all
    @submissions = Submission.includes(:user, :exercise).order(created_at: :desc).limit(10)
  end
  
  private
  
  def require_admin
    unless current_user.admin?
      redirect_to root_path, alert: 'Access denied'
    end
  end
end
