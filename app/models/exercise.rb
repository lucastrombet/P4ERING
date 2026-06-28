class Exercise < ApplicationRecord
  has_many :submissions, dependent: :destroy
  
  validates :title, :description, :language, presence: true
  validates :difficulty, presence: true, inclusion: { in: 1..5 }
  
  LANGUAGES = ['P4', 'Python', 'JavaScript', 'Ruby', 'Java', 'C++', 'Go', 'Rust']
  
  def difficulty_label
    case difficulty
    when 1 then 'Beginner'
    when 2 then 'Easy'
    when 3 then 'Intermediate'
    when 4 then 'Advanced'
    when 5 then 'Expert'
    end
  end

end
