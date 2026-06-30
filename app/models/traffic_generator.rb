class TrafficGenerator < ApplicationRecord
  has_many :exercise_traffic_generators, dependent: :destroy
  has_many :exercises, through: :exercise_traffic_generators

  PROTOCOLS = %w[TCP UDP].freeze

  validates :name,     presence: true, uniqueness: true
  validates :protocol, inclusion: { in: PROTOCOLS }
  validates :duration, numericality: { greater_than: 0 }
  validates :port,     numericality: { in: 1..65535 }
  validates :parallel_streams, numericality: { greater_than: 0 }, allow_nil: true

  def to_iperf_command(server_host)
    args = ["iperf3", "-c", server_host, "-p", port.to_s, "-t", duration.to_s, "-i", interval.to_s]
    args << "-u"                         if protocol == "UDP"
    args += ["-b", bandwidth]            if bandwidth.present?
    args += ["-P", parallel_streams.to_s] if parallel_streams.to_i > 1
    args += ["-l", packet_length]        if packet_length.present?
    args << "-R"                         if reverse?
    args += ["-S", tos]                  if tos.present?
    args.join(" ")
  end
end
