class Professor::ClassroomsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_professor
  before_action :set_classroom, only: [:show, :edit, :update, :destroy]

  def index
    @classrooms = current_user.classrooms_as_professor.order(created_at: :desc)
  end

  def show
    @students            = @classroom.students.order(:name)
    @classroom_exercises = @classroom.classroom_exercises.includes(:exercise).order(:start_date)
    @available_students  = User.where(admin: false, professor: false)
                               .where.not(id: @students.pluck(:id))
                               .order(:name)
    @available_exercises = Exercise.where.not(id: @classroom.exercise_ids).order(:title)
    @completion_stats    = build_completion_stats
  end

  def new
    @classroom = Classroom.new
  end

  def create
    @classroom = Classroom.new(classroom_params)
    @classroom.professor = current_user
    if @classroom.save
      redirect_to professor_classroom_path(@classroom), notice: 'Classroom created successfully.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @classroom.update(classroom_params)
      redirect_to professor_classroom_path(@classroom), notice: 'Classroom updated successfully.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @classroom.destroy
    redirect_to professor_classrooms_path, notice: 'Classroom deleted.'
  end

  private

  def set_classroom
    @classroom = current_user.classrooms_as_professor.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to professor_classrooms_path, alert: 'Classroom not found.'
  end

  def classroom_params
    params.require(:classroom).permit(:name, :description, :start_date, :end_date)
  end

  def require_professor
    redirect_to root_path, alert: 'Access denied.' unless current_user.staff?
  end

  def build_completion_stats
    student_ids  = @students.pluck(:id)
    exercise_ids = @classroom_exercises.map { |ce| ce.exercise_id }
    return {} if student_ids.empty? || exercise_ids.empty?

    completed = Submission.where(user_id: student_ids, exercise_id: exercise_ids, status: 'completed')
                          .group(:exercise_id, :user_id)
                          .pluck(:exercise_id, :user_id)
                          .group_by(&:first)
                          .transform_values { |rows| rows.map(&:last) }

    exercise_ids.index_with do |eid|
      done     = (completed[eid] || []).uniq
      not_done = student_ids - done
      { completed: done, not_completed: not_done }
    end
  end
end
