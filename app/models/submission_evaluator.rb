# Automated grading for a P4 submission: given the exercise's
# `evaluation_criteria` JSON and the structured (header-decoded) packet
# captures produced by p4exec for each host, decides whether the
# submission's traffic behavior matches what the exercise expects.
#
# There is deliberately no positional/count-based pairing between two
# hosts' captures — an exercise like a firewall can legitimately drop
# packets, so before/after correspondence is established per-check (by
# matching L4 payload bytes, which a header-rewriting P4 program leaves
# untouched) rather than assumed globally. See the criteria spec examples
# in the checks below for each kind's shape.
class SubmissionEvaluator
  include PacketChecksum

  Result = Struct.new(:passed, :checks, keyword_init: true) do
    def as_json(*)
      { passed: passed, checks: checks.map(&:as_json) }
    end
  end

  CheckResult = Struct.new(:kind, :description, :passed, :expected, :actual, keyword_init: true) do
    def as_json(*)
      { kind: kind, description: description, passed: passed, expected: expected, actual: actual }
    end
  end

  def initialize(criteria:, structured_captures:, traffic_metrics: nil)
    @criteria = criteria || {}
    @captures = structured_captures || {}
    @traffic_metrics = Array(traffic_metrics)
  end

  def evaluate
    checks = Array(@criteria['checks']).map { |check| run_check(check) }
    Result.new(passed: checks.all?(&:passed), checks: checks)
  end

  private :valid_checksum?

  private

  def run_check(check)
    case check['kind']
    when 'transformation' then transformation_check(check)
    when 'count'          then count_check(check)
    when 'checksum'       then checksum_check(check)
    when 'duplication'    then duplication_check(check)
    when 'traffic_metric' then traffic_metric_check(check)
    else
      CheckResult.new(kind: check['kind'], description: "Unknown check kind: #{check['kind']}",
                       passed: false, expected: nil, actual: nil)
    end
  end

  # { "kind": "transformation", "from": "h1", "to": "h2",
  #   "layer": "ethernet", "field": "src_mac", "op": "equals"|"unchanged"|"changed",
  #   "value": ... (only for "equals"),
  #   "filter": { "layer": "icmp", "type": 8 } (optional — restricts which
  #     "from"-side packets are considered, e.g. request-only so a
  #     bidirectional exchange's replies don't get pulled into the same
  #     check with the opposite expected direction) }
  def transformation_check(check)
    layer, field, op = check['layer'], check['field'], check['op']
    description = "#{check['from']} -> #{check['to']}: #{layer}.#{field} #{op}" \
                  "#{op == 'equals' ? " #{check['value']}" : ''}"

    pairs = correlated_pairs(check['from'], check['to'], check['filter'])
    if pairs.empty?
      return CheckResult.new(kind: 'transformation', description: description, passed: false,
                              expected: 'at least one correlated before/after packet',
                              actual: 'no matching payloads found between captures')
    end

    failure = nil
    pairs.each do |before_pkt, after_pkt|
      before_val = before_pkt.dig(layer, field)
      after_val  = after_pkt.dig(layer, field)
      ok = case op
           when 'equals'    then normalize(after_val) == normalize(check['value'])
           when 'unchanged' then normalize(after_val) == normalize(before_val)
           when 'changed'   then normalize(after_val) != normalize(before_val)
           else false
           end
      next if ok
      failure ||= {
        expected: op == 'unchanged' ? before_val : (op == 'equals' ? check['value'] : "different from #{before_val}"),
        actual: after_val,
      }
    end

    CheckResult.new(kind: 'transformation', description: description, passed: failure.nil?,
                    expected: failure&.dig(:expected), actual: failure&.dig(:actual))
  end

  # { "kind": "count", "capture": "h2",
  #   "filter": { "layer": "tcp", "dst_port": 23 }, "op": "equals"|"lte"|"gte", "value": 0 }
  def count_check(check)
    packets = capture_for(check['capture'])
    count   = packets.count { |pkt| matches_filter?(pkt, check['filter']) }
    op, value = check['op'], check['value']
    ok = compare(count, op, value)

    description = "count of packets matching #{check['filter']} in #{check['capture']} #{op} #{value}"
    CheckResult.new(kind: 'count', description: description, passed: ok,
                    expected: "#{op} #{value}", actual: count)
  end

  # { "kind": "checksum", "capture": "h2", "layer": "ipv4"|"icmp"|"tcp"|"udp" }
  def checksum_check(check)
    layer   = check['layer']
    packets = capture_for(check['capture']).select { |pkt| pkt[layer] }
    invalid = packets.reject { |pkt| valid_checksum?(pkt, layer) }

    description = "#{layer} checksum valid for every packet in #{check['capture']}"
    CheckResult.new(kind: 'checksum', description: description, passed: invalid.empty?,
                    expected: 'valid checksum on every packet',
                    actual: invalid.empty? ? 'all valid' : "#{invalid.size}/#{packets.size} invalid")
  end

  # { "kind": "duplication", "from": "h1", "to": "h2", "op": "lte"|"gte"|"equals", "value": 1,
  #   "filter": { "layer": "icmp", "type": 8 } (optional, see transformation_check) }
  def duplication_check(check)
    from_packets = capture_for(check['from'])
    from_packets = from_packets.select { |pkt| matches_filter?(pkt, check['filter']) } if check['filter'].present?
    from_map = payload_map(from_packets)
    to_map   = payload_map(capture_for(check['to']))
    op, value = check['op'], check['value']

    counts = from_map.keys.map { |payload| to_map.fetch(payload, []).size }
    worst  = counts.select { |count| !compare(count, op, value) }

    description = "duplication count #{op} #{value} (#{check['from']} -> #{check['to']})"
    CheckResult.new(kind: 'duplication', description: description, passed: worst.empty?,
                    expected: "#{op} #{value}", actual: worst.empty? ? counts.max || 0 : worst.max)
  end

  # { "kind": "traffic_metric", "flow": 1 (1-based index into the run's
  #   traffic tests — legacy traffic_test is flow 1 when present, generator
  #   mappings follow in position order),
  #   "metric": "throughput_mbps"|"loss_percent"|"jitter_ms"|"retransmits",
  #   "op": "gte"|"lte"|"equals", "value": number }
  #
  # Metrics come from the iperf3 -J client report parsed by IperfReport in
  # the exec callback — performance grading (QoS/rate limiting/ECMP), which
  # packet-capture checks can't express.
  def traffic_metric_check(check)
    flow_idx, metric, op, value = check['flow'], check['metric'], check['op'], check['value']
    flow = @traffic_metrics[flow_idx.to_i - 1]

    description = "flow #{flow_idx}#{flow ? " (#{flow['label']})" : ''}: #{metric} #{op} #{value}"

    if flow.nil?
      return CheckResult.new(kind: 'traffic_metric', description: description, passed: false,
                             expected: "traffic flow ##{flow_idx} to have run",
                             actual: "run produced #{@traffic_metrics.size} traffic test(s)")
    end

    actual = flow['metrics'] && flow['metrics'][metric]
    if actual.nil?
      return CheckResult.new(kind: 'traffic_metric', description: description, passed: false,
                             expected: "#{metric} to be measured",
                             actual: flow['metrics'] ? "metric not present (protocol #{flow['metrics']['protocol']})" : 'no iperf metrics for this flow')
    end

    CheckResult.new(kind: 'traffic_metric', description: description,
                    passed: compare(actual, op, value),
                    expected: "#{op} #{value}", actual: actual)
  end

  # ── Correlation / filtering helpers ────────────────────────────────────────

  # Pairs up before/after packets across two captures by matching L4 payload
  # bytes (a header-rewriting P4 program leaves the payload untouched
  # regardless of which header fields it mutates). Packets with no
  # after-side match simply aren't included — that's what `count` checks
  # are for, not a transformation-check failure by itself.
  def correlated_pairs(from_host, to_host, filter = nil)
    from_packets = capture_for(from_host)
    from_packets = from_packets.select { |pkt| matches_filter?(pkt, filter) } if filter.present?
    from_map = payload_map(from_packets)
    to_map   = payload_map(capture_for(to_host))

    pairs = []
    from_map.each do |payload, before_list|
      # payload_map's Hash has an auto-vivifying default block, so a plain
      # `to_map[payload]` read would silently insert (and return) an empty
      # array for a payload with no match — .fetch bypasses that.
      after_list = to_map.fetch(payload, [])
      next if after_list.empty?
      before_list.each_with_index do |before_pkt, i|
        pairs << [before_pkt, after_list[i] || after_list.last]
      end
    end
    pairs
  end

  # Keyed on payload bytes plus ICMP type (when present) rather than
  # payload alone — an ICMP echo *reply* copies its request's payload
  # verbatim (RFC 792), so payload-only keys would conflate a request
  # with an unrelated reply that happens to carry the same data.
  def payload_map(packets)
    map = Hash.new { |h, k| h[k] = [] }
    packets.each { |pkt| map[[pkt['payload'], pkt.dig('icmp', 'type')]] << pkt }
    map
  end

  def capture_for(host_name)
    Array(@captures[host_name.to_s])
  end

  def matches_filter?(packet, filter)
    return true if filter.blank?
    layer = filter['layer']
    return false unless packet[layer]
    filter.each do |key, expected|
      next if key == 'layer'
      return false unless packet.dig(layer, key) == expected
    end
    true
  end

  def compare(actual, op, expected)
    case op
    when 'equals' then actual == expected
    when 'lte'    then actual <= expected
    when 'gte'    then actual >= expected
    else false
    end
  end

  def normalize(value)
    value.is_a?(String) ? value.downcase : value
  end
end
