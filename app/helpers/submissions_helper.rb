module SubmissionsHelper
  PROTO_ROW_CLASS = {
    'ICMP'    => 'table-warning',
    'TCP'     => 'table-primary',
    'UDP'     => 'table-success',
    'ARP'     => 'table-secondary',
  }.freeze

  # Parse raw tcpdump text (from -n -e -tt flags) into an array of packet hashes.
  def parse_tcpdump_output(raw)
    return [] if raw.blank?

    base_ts = nil
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
      base_ts ||= ts

      ethertype = m[4].strip
      detail    = m[6].to_s.strip
      src, dst, proto = classify_packet(ethertype, detail)

      packets << {
        no:      packets.size + 1,
        time:    "%.3f" % (ts - base_ts),
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
      if detail =~ /\A(\d+\.\d+\.\d+\.\d+)\s+>\s+(\d+\.\d+\.\d+\.\d+):\s+(.*)/
        src, dst, rest = $1, $2, $3
        proto = case rest
                when /ICMP/i then 'ICMP'
                when /\bUDP\b/i then 'UDP'
                when /\bTCP\b/i then 'TCP'
                else 'IPv4'
                end
        return src, dst, proto
      end
    end

    [nil, nil, ethertype.gsub(/\s*\(.*?\)/, '').strip.upcase.presence || 'ETH']
  end
end
