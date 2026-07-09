class Professor::Classrooms::ExercisesController < ApplicationController
  before_action :authenticate_user!
  before_action :require_professor
  before_action :set_classroom
  before_action :set_classroom_exercise, only: [:show, :destroy]

  def show
    @exercise   = @classroom_exercise.exercise
    @students   = @classroom.students.order(:name)
    student_ids = @students.pluck(:id)

    submissions = Submission.where(user_id: student_ids, exercise_id: @exercise.id)
                            .order(created_at: :desc)

    @submissions_by_student = @students.index_with do |student|
      submissions.select { |s| s.user_id == student.id }
    end
  end

  def create
    # Not just any exercise id — it must be one this professor can see
    # (their own or one shared by its owner). Guards against forged ids.
    unless Exercise.visible_to(current_user).exists?(id: exercise_params[:exercise_id])
      return redirect_to professor_classroom_path(@classroom),
                         alert: t('admin.exercises.flash.not_visible')
    end

    @classroom_exercise = @classroom.classroom_exercises.build(exercise_params)
    if @classroom_exercise.save
      redirect_to professor_classroom_path(@classroom), notice: 'Exercise added to classroom.'
    else
      redirect_to professor_classroom_path(@classroom),
                  alert: @classroom_exercise.errors.full_messages.to_sentence
    end
  end

  def destroy
    ce = @classroom.classroom_exercises.find(params[:id])
    ce.destroy
    redirect_to professor_classroom_path(@classroom), notice: 'Exercise removed from classroom.'
  end

  private

  def set_classroom
    @classroom = current_user.classrooms_as_professor.find(params[:classroom_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to professor_classrooms_path, alert: 'Classroom not found.'
  end

  def set_classroom_exercise
    @classroom_exercise = @classroom.classroom_exercises.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to professor_classroom_path(@classroom), alert: 'Exercise not found.'
  end

  def exercise_params
    params.require(:classroom_exercise).permit(:exercise_id, :start_date, :end_date)
  end

  def require_professor
    redirect_to root_path, alert: 'Access denied.' unless current_user.staff?
  end
end
