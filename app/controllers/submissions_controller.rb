class SubmissionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_exercise, only: [:new, :create]
  before_action :set_submission, only: [:show, :run]
  
  def index
    @submissions = current_user.submissions.includes(:exercise).order(created_at: :desc)
  end
  
  def show
  end
  
  def new
    @submission = Submission.new
  end
  
  def create
    @submission = current_user.submissions.new(submission_params)
    @submission.exercise = @exercise
    @submission.status = 'pending'
    
    if @submission.save
      redirect_to @submission, notice: 'Code submitted successfully!'
    else
      render :new, status: :unprocessable_entity
    end
  end
  
  def run
    @submission.evaluate_code if @submission.respond_to?(:evaluate_code)
    redirect_to @submission, notice: 'Code execution completed!'
  end
  
  private
  
  def set_exercise
    @exercise = Exercise.find(params[:exercise_id])
  end
  
  def set_submission
    @submission = Submission.find(params[:id])
  end
  
  def submission_params
    params.require(:submission).permit(:code)
  end
end
