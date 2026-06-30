class ExerciseTrafficGenerator < ApplicationRecord
  belongs_to :exercise
  belongs_to :traffic_generator
end
