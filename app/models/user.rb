class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :submissions, dependent: :destroy
  has_many :classrooms_as_professor, class_name: 'Classroom', foreign_key: :professor_id, dependent: :destroy
  has_many :classroom_enrollments, dependent: :destroy
  has_many :classrooms, through: :classroom_enrollments

  validates :name, presence: true, on: :update
  validates :name, presence: true, on: :create

  def admin?
    admin
  end

  def professor?
    professor
  end

  def staff?
    admin? || professor?
  end
end
