class Exercise < ApplicationRecord
  has_many :submissions, dependent: :destroy
  has_many :classroom_exercises, dependent: :destroy
  has_many :classrooms, through: :classroom_exercises
  has_many :exercise_traffic_generators, dependent: :destroy
  has_many :traffic_generators, through: :exercise_traffic_generators

  validates :title, :description, :language, presence: true
  validates :difficulty, presence: true, inclusion: { in: 1..5 }
  validate :topology_config_valid_json
  validate :evaluation_criteria_valid_json

  LANGUAGES = ['P4'].freeze

  DIFFICULTY_KEYS = { 1 => :beginner, 2 => :easy, 3 => :intermediate, 4 => :advanced, 5 => :expert }.freeze

  def difficulty_label
    key = DIFFICULTY_KEYS[difficulty]
    key && I18n.t("exercises.difficulty.#{key}")
  end

  def has_topology?
    topology_config.present?
  end

  def parsed_topology
    JSON.parse(topology_config) if topology_config.present?
  rescue JSON::ParserError
    nil
  end

  def has_evaluation_criteria?
    evaluation_criteria.present?
  end

  def parsed_evaluation_criteria
    JSON.parse(evaluation_criteria) if evaluation_criteria.present?
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

  def evaluation_criteria_valid_json
    return if evaluation_criteria.blank?
    JSON.parse(evaluation_criteria)
  rescue JSON::ParserError => e
    errors.add(:evaluation_criteria, "is not valid JSON: #{e.message}")
  end
end
