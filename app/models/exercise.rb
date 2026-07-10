class Exercise < ApplicationRecord
  belongs_to :owner, class_name: 'User', foreign_key: :user_id, optional: true
  has_many :submissions, dependent: :destroy
  has_many :classroom_exercises, dependent: :destroy
  has_many :classrooms, through: :classroom_exercises
  has_many :exercise_traffic_generators, -> { order(:position, :id) },
           dependent: :destroy, inverse_of: :exercise
  has_many :traffic_generators, through: :exercise_traffic_generators

  accepts_nested_attributes_for :exercise_traffic_generators,
                                allow_destroy: true,
                                reject_if: ->(attrs) { attrs['traffic_generator_id'].blank? }

  # What a staff member can see and attach to their classrooms: admins see
  # everything; a professor sees their own exercises plus the ones other
  # professors chose to share. (Student visibility is a separate concern —
  # that's the `restricted` flag.)
  scope :visible_to, ->(user) {
    user.admin? ? all : where(visible_by_other_professors: true).or(where(user_id: user.id))
  }

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

  def owned_by?(user)
    user_id.present? && user_id == user.id
  end

  def visible_to?(user)
    user.admin? || owned_by?(user) || visible_by_other_professors?
  end

  # Attached to at least one classroom. While in use, the exercise is
  # frozen for everyone — owner and admins alike — so it can't change (or
  # vanish) under enrolled students; detach it from all classrooms first.
  def in_use?
    classroom_exercises.exists?
  end

  def editable_by?(user)
    !in_use? && (user.admin? || owned_by?(user))
  end

  # A modifiable copy owned by `user` — how a professor builds on another
  # professor's (or a locked) exercise instead of editing it in place.
  def duplicate_for(user)
    copy = dup
    copy.owner = user
    copy.title = "#{title} (#{I18n.t('exercises.copy_suffix')})"
    copy.exercise_traffic_generators = exercise_traffic_generators.map(&:dup)
    copy
  end

  def has_topology?
    topology_config.present?
  end

  def topology_host_names
    (parsed_topology&.dig('connections') || []).filter_map { |c| c['host_name'].presence }
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
