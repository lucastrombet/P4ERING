class Submission < ApplicationRecord
  belongs_to :user
  belongs_to :exercise

  validates :code, presence: true

  STATUSES = ['pending', 'completed', 'failed', 'evaluating']

  def parsed_packet_captures
    JSON.parse(packet_captures) if packet_captures.present?
  rescue JSON::ParserError
    nil
  end

  # Per-host arrays of header-decoded packet dicts (see pcap.py#decode_frame
  # on the p4exec side), in the same capture order as parsed_packet_captures'
  # tcpdump text lines for that host — the packet at 1-based row `no` in the
  # text table is structured_packet_captures[host][no - 1]. Used to render
  # the expandable Wireshark-style field tree per packet.
  def parsed_structured_packet_captures
    JSON.parse(structured_packet_captures) if structured_packet_captures.present?
  rescue JSON::ParserError
    nil
  end

  def parsed_evaluation_result
    JSON.parse(evaluation_result) if evaluation_result.present?
  rescue JSON::ParserError
    nil
  end

  # after_create_commit (not after_create) — EvaluateSubmissionJob queries this
  # row from a background thread, which can race the enclosing transaction's
  # commit under the :async adapter (development) and see nothing if this
  # fired inside it. Same fix as GameSession#after_create_commit.
  after_create_commit :queue_evaluation

  private

  def queue_evaluation
    EvaluateSubmissionJob.perform_later(id)
  end
end
