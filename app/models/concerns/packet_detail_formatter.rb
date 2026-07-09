module PacketDetailFormatter
  LAYER_ORDER = %w[ethernet ipv4 ipv6 icmp tcp udp].freeze

  ETHERTYPES   = { 0x0800 => 'IPv4', 0x86DD => 'IPv6', 0x0806 => 'ARP' }.freeze
  IP_PROTOCOLS = { 1 => 'ICMP', 6 => 'TCP', 17 => 'UDP', 58 => 'ICMPv6' }.freeze
  ICMP_TYPES   = { 0 => 'Echo Reply', 3 => 'Destination Unreachable', 8 => 'Echo Request',
                    11 => 'Time Exceeded', 128 => 'Echo Request (v6)', 129 => 'Echo Reply (v6)' }.freeze
  TCP_FLAG_BITS = [
    [0x001, 'FIN'], [0x002, 'SYN'], [0x004, 'RST'], [0x008, 'PSH'],
    [0x010, 'ACK'], [0x020, 'URG'], [0x040, 'ECE'], [0x080, 'CWR'], [0x100, 'NS'],
  ].freeze

  # Checksum byte offsets within each layer's `raw` hex blob — same offsets
  # SubmissionEvaluator#valid_*_checksum? uses to recompute and validate
  # them; kept in sync deliberately so the displayed value always matches
  # what grading actually checks.
  CHECKSUM_OFFSET = { 'ipv4' => 10, 'icmp' => 2, 'tcp' => 16, 'udp' => 6 }.freeze

  # Given one decoded packet dict (see p4pydockerexec-service/pcap.py
  # #decode_frame) returns an ordered array of
  # { key:, label:, summary:, fields: [[label, value], ...] } describing
  # each present protocol layer, for rendering a Wireshark-style
  # collapsible field tree — `summary` is the terse "Src: x, Dst: y" line
  # shown next to the layer name on its (collapsed-by-default) header, the
  # same way Wireshark's own packet detail pane does, so the header is
  # informative even before the layer is expanded.
  def packet_detail_layers(pkt)
    return [] if pkt.blank?

    layers = LAYER_ORDER.filter_map do |key|
      data = pkt[key]
      next unless data

      fields = send("format_#{key}_fields", data).reject { |_, value| value.nil? }
      summary = respond_to?("summary_#{key}", true) ? send("summary_#{key}", data, pkt) : nil
      { key: key, label: layer_label(key), summary: summary, fields: fields }
    end

    if pkt['payload'].present?
      layers << { key: 'payload', label: layer_label('payload'), summary: nil, fields: format_payload_fields(pkt['payload']) }
    end

    layers
  end

  private

  def layer_label(key)
    I18n.t("submissions.packet_captures.detail.layers.#{key}")
  end

  def field_label(key)
    I18n.t("submissions.packet_captures.detail.fields.#{key}")
  end

  def format_ethernet_fields(data)
    [
      [field_label(:dst_mac), data['dst_mac']],
      [field_label(:src_mac), data['src_mac']],
      [field_label(:ethertype), format_hex_lookup(data['ethertype'], ETHERTYPES, width: 4)],
    ]
  end

  def format_ipv4_fields(data)
    [
      [field_label(:src), data['src']],
      [field_label(:dst), data['dst']],
      [field_label(:ttl), data['ttl']],
      [field_label(:protocol), format_dec_lookup(data['protocol'], IP_PROTOCOLS)],
      [field_label(:header_len), byte_count(data['header_len'])],
      [field_label(:checksum), extract_checksum_hex(data['raw'], 'ipv4')],
    ]
  end

  def format_ipv6_fields(data)
    [
      [field_label(:src), data['src']],
      [field_label(:dst), data['dst']],
      [field_label(:hop_limit), data['hop_limit']],
      [field_label(:next_header), format_dec_lookup(data['next_header'], IP_PROTOCOLS)],
    ]
  end

  def format_icmp_fields(data)
    fields = [
      [field_label(:type), format_dec_lookup(data['type'], ICMP_TYPES)],
      [field_label(:code), data['code']],
    ]
    fields << [field_label(:id), data['id']] if data['id']
    fields << [field_label(:seq), data['seq']] if data['seq']
    fields << [field_label(:checksum), extract_checksum_hex(data['raw'], 'icmp')]
    fields
  end

  def format_tcp_fields(data)
    [
      [field_label(:src_port), data['src_port']],
      [field_label(:dst_port), data['dst_port']],
      [field_label(:seq), data['seq']],
      [field_label(:ack), data['ack']],
      [field_label(:flags), format_tcp_flags(data['flags'])],
      [field_label(:header_len), byte_count(data['header_len'])],
      [field_label(:checksum), extract_checksum_hex(data['raw'], 'tcp')],
    ]
  end

  def format_udp_fields(data)
    [
      [field_label(:src_port), data['src_port']],
      [field_label(:dst_port), data['dst_port']],
      [field_label(:length), byte_count(data['length'])],
      [field_label(:checksum), extract_checksum_hex(data['raw'], 'udp')],
    ]
  end

  def format_payload_fields(hex)
    byte_len = hex.to_s.length / 2
    shown    = hex.to_s[0, 512]
    hex_str  = hex.to_s.length > 512 ? "#{shown}…" : shown
    [[field_label(:bytes), byte_len], [field_label(:hex), hex_str]]
  end

  # Terse "Src: x, Dst: y" summaries shown on each (collapsed-by-default)
  # layer header, mirroring Wireshark's own packet detail pane. These
  # abbreviations (Src/Dst/Seq/Ack/Len...) are Wireshark's own convention
  # and, like TTL elsewhere in this app, are left untranslated even in the
  # pt-BR locale — they're effectively technical shorthand, not prose.

  def summary_ethernet(data, _pkt)
    "Src: #{data['src_mac']}, Dst: #{data['dst_mac']}"
  end

  def summary_ipv4(data, _pkt)
    "Src: #{data['src']}, Dst: #{data['dst']}"
  end

  def summary_ipv6(data, _pkt)
    "Src: #{data['src']}, Dst: #{data['dst']}"
  end

  def summary_icmp(data, _pkt)
    "Type: #{format_dec_lookup(data['type'], ICMP_TYPES)}, Code: #{data['code']}"
  end

  def summary_tcp(data, pkt)
    "Src Port: #{data['src_port']}, Dst Port: #{data['dst_port']}, " \
      "Seq: #{data['seq']}, Ack: #{data['ack']}, Len: #{payload_byte_count(pkt)}"
  end

  def summary_udp(data, pkt)
    "Src Port: #{data['src_port']}, Dst Port: #{data['dst_port']}, Len: #{payload_byte_count(pkt)}"
  end

  def payload_byte_count(pkt)
    pkt['payload'].to_s.length / 2
  end

  def byte_count(n)
    return nil if n.nil?
    I18n.t('submissions.packet_captures.detail.byte_count', count: n)
  end

  def format_hex_lookup(value, table, width:)
    return nil if value.nil?
    hex  = format("0x%0#{width}x", value)
    name = table[value]
    name ? "#{hex} (#{name})" : hex
  end

  def format_dec_lookup(value, table)
    return nil if value.nil?
    name = table[value]
    name ? "#{value} (#{name})" : value.to_s
  end

  def format_tcp_flags(bitmask)
    return nil if bitmask.nil?
    set = TCP_FLAG_BITS.select { |bit, _| bitmask & bit != 0 }.map(&:last)
    format('0x%03x (%s)', bitmask, set.any? ? set.join(', ') : '—')
  end

  # `raw` is the hex-encoded remainder of the frame from that layer onward
  # (header + payload) — see pcap.py#decode_frame's docstring. The checksum
  # field always sits at CHECKSUM_OFFSET[layer] bytes into it.
  def extract_checksum_hex(raw_hex, layer)
    return nil if raw_hex.blank?
    start = CHECKSUM_OFFSET.fetch(layer) * 2
    chunk = raw_hex[start, 4]
    chunk && chunk.length == 4 ? "0x#{chunk}" : nil
  end
end
