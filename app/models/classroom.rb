class Classroom < ApplicationRecord
  belongs_to :professor, class_name: 'User'
  has_many :classroom_enrollments, dependent: :destroy
  has_many :students, through: :classroom_enrollments, source: :user
  has_many :classroom_exercises, dependent: :destroy
  has_many :exercises, through: :classroom_exercises

  validates :name, :description, :start_date, :end_date, presence: true
  validate :end_date_after_start_date
  validates :date_enrollment, presence: true, if: :self_enrollment?
  validate :date_enrollment_within_course, if: :self_enrollment?

  # Joinable through the public self-enrollment page: opted in by the
  # professor and still within the enrollment deadline.
  scope :open_for_enrollment, -> {
    where(self_enrollment: true).where('date_enrollment >= ?', Date.current)
  }

  # Anyone can join as a student — including professors/admins wanting to
  # experience the course from the student side — except the classroom's
  # own professor.
  def enrollable_by?(user)
    self_enrollment? &&
      date_enrollment.present? && date_enrollment >= Date.current &&
      user.id != professor_id &&
      !students.exists?(user.id)
  end

  private

  def end_date_after_start_date
    return unless start_date && end_date
    errors.add(:end_date, 'must be after start date') if end_date <= start_date
  end

  # Enrolling after the course ended makes no sense; before the course
  # starts is fine (that's the normal registration period).
  def date_enrollment_within_course
    return unless date_enrollment && end_date
    errors.add(:date_enrollment, :after_course_end) if date_enrollment > end_date
  end
end
