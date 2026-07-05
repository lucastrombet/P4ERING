# app/controllers/admin/exercises_controller.rb
class Admin::ExercisesController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin
  before_action :set_exercise, only: [:edit, :update, :destroy]
  
  def index
    @exercises = Exercise.all.order(created_at: :desc)
  end
  
  def new
    @exercise = Exercise.new
  end
  
  def create
    @exercise = Exercise.new(exercise_params)
    
    if @exercise.save
      redirect_to admin_exercises_path, notice: 'Exercise was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end
  
  def edit
  end
  
  def update
    if @exercise.update(exercise_params)
      redirect_to admin_exercises_path, notice: 'Exercise was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end
  
  def destroy
    @exercise.destroy
    redirect_to admin_exercises_path, notice: 'Exercise was successfully deleted.'
  end
  
  private
  
  def set_exercise
    @exercise = Exercise.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to admin_exercises_path, alert: 'Exercise not found.'
  end
  
  def exercise_params
    params.require(:exercise).permit(:title, :description, :language, :difficulty,
                                     :starter_code, :topology_config, :restricted,
                                     traffic_generator_ids: [])
  end
  
  def require_admin
    unless current_user.staff?
      redirect_to root_path, alert: 'Access denied.'
    end
  end
end
