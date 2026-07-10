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

  # The topology as sent to p4exec: the exercise's traffic-generator
  # mappings rendered into concrete commands and injected as
  # `traffic_tests` alongside the topology's own legacy `traffic_test`
  # (which p4exec still runs first if present). Both commands are built
  # here so p4exec stays a dumb executor with no iperf knowledge: the
  # one-shot server (-1) on the target host, and the client on the source
  # host aimed at the target's topology IP (-J for the metrics report).
  def topology_for_execution
    topo = parsed_topology
    return topo unless topo

    host_ips = (topo['connections'] || []).to_h do |c|
      [c['host_name'], c['host_ip'].to_s.split('/').first]
    end

    tests = exercise_traffic_generators.includes(:traffic_generator).filter_map do |m|
      gen       = m.traffic_generator
      target_ip = host_ips[m.to_host]
      next if target_ip.blank?

      {
        'from'           => m.from_host,
        'to'             => m.to_host,
        'label'          => "#{gen.name} (#{m.from_host} -> #{m.to_host})",
        'server_command' => "iperf3 -s -p #{gen.port} -1",
        'client_command' => "#{gen.to_iperf_command(target_ip)} -J"
      }
    end

    tests.any? ? topo.merge('traffic_tests' => tests) : topo
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
