class ClassroomExercise < ApplicationRecord
  belongs_to :classroom
  belongs_to :exercise

  validates :start_date, :end_date, presence: true
  validates :exercise_id, uniqueness: { scope: :classroom_id }
  validate :end_date_after_start_date

  private

  def end_date_after_start_date
    return unless start_date && end_date
    errors.add(:end_date, 'must be after start date') if end_date <= start_date
  end
end
