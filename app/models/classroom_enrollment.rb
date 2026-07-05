class ClassroomEnrollment < ApplicationRecord
  belongs_to :classroom
  belongs_to :user

  validates :user_id, uniqueness: { scope: :classroom_id }
end
