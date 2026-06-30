class Exercise < ApplicationRecord
  has_many :submissions, dependent: :destroy
  has_many :exercise_traffic_generators, dependent: :destroy
  has_many :traffic_generators, through: :exercise_traffic_generators

  validates :title, :description, :language, presence: true
  validates :difficulty, presence: true, inclusion: { in: 1..5 }
  validate :topology_config_valid_json

  LANGUAGES = ['P4'].freeze

  def difficulty_label
    case difficulty
    when 1 then 'Beginner'
    when 2 then 'Easy'
    when 3 then 'Intermediate'
    when 4 then 'Advanced'
    when 5 then 'Expert'
    end
  end

  def has_topology?
    topology_config.present?
  end

  def parsed_topology
    JSON.parse(topology_config) if topology_config.present?
  rescue JSON::ParserError
    nil
  end

  private

  def topology_config_valid_json
    return if topology_config.blank?
    JSON.parse(topology_config)
  rescue JSON::ParserError => e
    errors.add(:topology_config, "is not valid JSON: #{e.message}")
  end
end
