class Classroom < ApplicationRecord
  belongs_to :professor, class_name: 'User'
  has_many :classroom_enrollments, dependent: :destroy
  has_many :students, through: :classroom_enrollments, source: :user
  has_many :classroom_exercises, dependent: :destroy
  has_many :exercises, through: :classroom_exercises

  validates :name, :description, :start_date, :end_date, presence: true
  validate :end_date_after_start_date

  private

  def end_date_after_start_date
    return unless start_date && end_date
    errors.add(:end_date, 'must be after start date') if end_date <= start_date
  end
end
