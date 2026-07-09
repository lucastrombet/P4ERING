module TcpdumpParser
  PROTO_ROW_CLASS = {
    'ICMP'    => 'table-warning',
    'TCP'     => 'table-primary',
    'UDP'     => 'table-success',
    'ARP'     => 'table-secondary',
  }.freeze

  # Parse raw tcpdump text (from -n -e -tt flags) into an array of packet
  # hashes. By default the "time" column is relative to the first packet in
  # `raw` (fine for a one-shot capture parsed once). Pass `base_ts: false`
  # to show tcpdump's absolute timestamp instead — needed for incremental
  # batches (e.g. the live game view), since each batch is parsed in its own
  # stateless request and restarting "time since first packet" at zero on
  # every batch would be nonsensical.
  def parse_tcpdump_output(raw, base_ts: true)
    return [] if raw.blank?

    first_ts = nil
    packets = []

    raw.each_line.each_with_index do |line, idx|
      line = line.chomp
      next if line.blank?
      next if line =~ /\A\d+ packets (captured|received|dropped)/i
      next if line =~ /\Alistening on/i

      # TIMESTAMP SRC_MAC > DST_MAC, ethertype INFO, length N: DETAIL
      m = line.match(
        /\A(\d+\.\d+)\s+
         ([0-9a-f]{2}(?::[0-9a-f]{2}){5})\s+>\s+
         ([0-9a-f]{2}(?::[0-9a-f]{2}){5}),\s+
         ethertype\s+(.+?),\s+
         length\s+(\d+)
         (?::\s+(.*))?
        \z/xi
      )
      next unless m

      ts = m[1].to_f
      first_ts ||= ts

      ethertype = m[4].strip
      detail    = m[6].to_s.strip
      src, dst, proto = classify_packet(ethertype, detail)

      packets << {
        no:      packets.size + 1,
        time:    base_ts ? ("%.3f" % (ts - first_ts)) : ("%.3f" % ts),
        src:     src || m[2],
        dst:     dst || m[3],
        src_mac: m[2],
        dst_mac: m[3],
        proto:   proto,
        length:  m[5].to_i,
        info:    detail.length > 90 ? "#{detail[0, 90]}…" : detail,
      }
    end

    packets
  end

  def proto_row_class(proto)
    PROTO_ROW_CLASS.fetch(proto.to_s.upcase, '')
  end

  private

  def classify_packet(ethertype, detail)
    return [nil, nil, 'ARP'] if ethertype =~ /ARP/i

    if ethertype =~ /IPv4|0x0800/i
      # TCP/UDP lines carry the port appended to each IP with a dot, same as
      # the address octets (e.g. "10.0.1.2.5000 > 10.0.2.2.6000: UDP, length
      # 20") — the trailing (?:\.\d+)? absorbs that without pulling it into
      # the captured address. Plain ICMP lines have no port suffix at all.
      if detail =~ /\A(\d+\.\d+\.\d+\.\d+)(?:\.\d+)?\s+>\s+(\d+\.\d+\.\d+\.\d+)(?:\.\d+)?:\s+(.*)/
        src, dst, rest = $1, $2, $3
        proto = case rest
                when /ICMP/i then 'ICMP'
                when /\bUDP\b/i then 'UDP'
                # TCP lines don't contain the literal word "TCP" in tcpdump's
                # default (non -v) output — they're identified by the
                # "Flags [...]" marker instead, e.g. "Flags [S], seq 123...".
                when /\bFlags\s*\[/i then 'TCP'
                else 'IPv4'
                end
        return src, dst, proto
      end
    end

    [nil, nil, ethertype.gsub(/\s*\(.*?\)/, '').strip.upcase.presence || 'ETH']
  end
end
