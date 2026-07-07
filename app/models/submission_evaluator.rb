require 'ipaddr'

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

  def initialize(criteria:, structured_captures:)
    @criteria = criteria || {}
    @captures = structured_captures || {}
  end

  def evaluate
    checks = Array(@criteria['checks']).map { |check| run_check(check) }
    Result.new(passed: checks.all?(&:passed), checks: checks)
  end

  private

  def run_check(check)
    case check['kind']
    when 'transformation' then transformation_check(check)
    when 'count'          then count_check(check)
    when 'checksum'       then checksum_check(check)
    when 'duplication'    then duplication_check(check)
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

  # ── Checksum validation ─────────────────────────────────────────────────────
  #
  # Standard Internet checksum (RFC 1071): one's-complement sum of 16-bit
  # words, carries folded back in, then one's-complemented. `raw` fields
  # from p4exec are hex strings of the *original* captured bytes (checksum
  # field included) so we zero that field out here before recomputing —
  # matching the sender-side algorithm exactly.

  def valid_checksum?(packet, layer)
    case layer
    when 'ipv4' then valid_ipv4_checksum?(packet)
    when 'icmp' then valid_icmp_checksum?(packet)
    when 'tcp'  then valid_l4_checksum?(packet, 'tcp', tcp_or_udp_protocol: 6)
    when 'udp'  then valid_udp_checksum?(packet)
    else true
    end
  end

  def valid_ipv4_checksum?(packet)
    bytes = hex_to_bytes(packet.dig('ipv4', 'raw'))
    return true if bytes.nil?
    original = (bytes[10] << 8) | bytes[11]
    bytes[10] = 0
    bytes[11] = 0
    internet_checksum(bytes) == original
  end

  # Plain ICMP (over IPv4) has no pseudo-header — the checksum covers only
  # the ICMP message itself. ICMPv6 does use a pseudo-header, like TCP/UDP.
  def valid_icmp_checksum?(packet)
    bytes = hex_to_bytes(packet.dig('icmp', 'raw'))
    return true if bytes.nil?

    if packet['ipv6']
      valid_l4_checksum?(packet, 'icmp', tcp_or_udp_protocol: 58)
    else
      original = (bytes[2] << 8) | bytes[3]
      bytes[2] = 0
      bytes[3] = 0
      internet_checksum(bytes) == original
    end
  end

  # UDP checksum is optional over IPv4 (RFC 768) — a wire value of 0 means
  # "not computed," which is not a bug to flag.
  def valid_udp_checksum?(packet)
    bytes = hex_to_bytes(packet.dig('udp', 'raw'))
    return true if bytes.nil?
    original = (bytes[6] << 8) | bytes[7]
    return true if original.zero? && packet['ipv4']
    valid_l4_checksum?(packet, 'udp', tcp_or_udp_protocol: 17)
  end

  # Builds the IPv4/IPv6 pseudo-header + segment (checksum field zeroed)
  # and compares against the checksum embedded in the original bytes.
  def valid_l4_checksum?(packet, layer, tcp_or_udp_protocol:)
    bytes = hex_to_bytes(packet.dig(layer, 'raw'))
    return true if bytes.nil?

    checksum_offset =
      case layer
      when 'tcp'  then 16
      when 'udp'  then 6
      when 'icmp' then 2
      end
    original = (bytes[checksum_offset] << 8) | bytes[checksum_offset + 1]
    bytes[checksum_offset]     = 0
    bytes[checksum_offset + 1] = 0

    pseudo_header = build_pseudo_header(packet, tcp_or_udp_protocol, bytes.length)
    return true if pseudo_header.nil?

    internet_checksum(pseudo_header + bytes) == original
  end

  def build_pseudo_header(packet, protocol, segment_length)
    if (ipv4 = packet['ipv4'])
      ipv4['src'].split('.').map(&:to_i) +
        ipv4['dst'].split('.').map(&:to_i) +
        [0, protocol, (segment_length >> 8) & 0xFF, segment_length & 0xFF]
    elsif (ipv6 = packet['ipv6'])
      ipv6_bytes(ipv6['src']) + ipv6_bytes(ipv6['dst']) +
        [(segment_length >> 24) & 0xFF, (segment_length >> 16) & 0xFF,
         (segment_length >> 8) & 0xFF, segment_length & 0xFF,
         0, 0, 0, protocol]
    end
  end

  def ipv6_bytes(address)
    IPAddr.new(address).hton.bytes
  end

  def hex_to_bytes(hex)
    return nil if hex.blank?
    [hex].pack('H*').bytes
  end

  def internet_checksum(bytes)
    bytes = bytes + [0] if bytes.length.odd?
    sum = 0
    bytes.each_slice(2) { |hi, lo| sum += (hi << 8) | lo }
    sum = (sum & 0xFFFF) + (sum >> 16) while sum > 0xFFFF
    (~sum) & 0xFFFF
  end
end
