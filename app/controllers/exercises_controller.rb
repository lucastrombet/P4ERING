class ExercisesController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin, except: [:index, :show]
  before_action :set_exercise, only: [:show, :edit, :update, :destroy]
  
  def index
    @exercises = Exercise.all.order(difficulty: :asc, created_at: :desc)
  end
  
  def show
    @submission = Submission.new
    @previous_submissions = current_user.submissions.where(exercise: @exercise).order(created_at: :desc)
  end
  
  def new
    @exercise = Exercise.new
  end
  
  def create
    @exercise = Exercise.new(exercise_params)
    
    if @exercise.save
      redirect_to @exercise, notice: 'Exercise was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end
  
  def edit
  end
  
  def update
    if @exercise.update(exercise_params)
      redirect_to @exercise, notice: 'Exercise was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end
  
  def destroy
    @exercise.destroy
    redirect_to exercises_path, notice: 'Exercise was successfully deleted.'
  end
  
  private
  
  def set_exercise
    @exercise = Exercise.find(params[:id])
  end
  
  def exercise_params
    params.require(:exercise).permit(:title, :description, :language, :difficulty)
  end
  
  def require_admin
    redirect_to root_path, alert: 'Access denied' unless current_user.admin?
  end
end
