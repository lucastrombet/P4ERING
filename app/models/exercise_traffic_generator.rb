class ExerciseTrafficGenerator < ApplicationRecord
  belongs_to :exercise
  belongs_to :traffic_generator

  validates :from_host, :to_host, presence: true
  validate  :hosts_differ
  validate  :hosts_exist_in_topology

  private

  def hosts_differ
    return if from_host.blank? || to_host.blank?
    errors.add(:to_host, :same_as_from) if from_host == to_host
  end

  # The mapping only makes sense between hosts that exist in this
  # exercise's topology — a typo here would fail silently at run time.
  def hosts_exist_in_topology
    return if exercise.nil? || from_host.blank? || to_host.blank?

    names = exercise.topology_host_names
    if names.empty?
      errors.add(:base, :no_topology_hosts)
      return
    end

    errors.add(:from_host, :not_in_topology, host: from_host) unless names.include?(from_host)
    errors.add(:to_host,   :not_in_topology, host: to_host)   unless names.include?(to_host)
  end
end
