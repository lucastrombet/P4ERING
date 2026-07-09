require 'ipaddr'

# Standard Internet checksum (RFC 1071) validation for decoded packet dicts
# (see p4pydockerexec-service/pcap.py#decode_frame). Extracted out of
# SubmissionEvaluator so the same validation logic can also drive the
# "Checksum Errors" packet-row coloring rule in PacketColoring, without
# duplicating the byte-level math in two places.
module PacketChecksum
  def valid_checksum?(packet, layer)
    case layer
    when 'ipv4' then valid_ipv4_checksum?(packet)
    when 'icmp' then valid_icmp_checksum?(packet)
    when 'tcp'  then valid_l4_checksum?(packet, 'tcp', tcp_or_udp_protocol: 6)
    when 'udp'  then valid_udp_checksum?(packet)
    else true
    end
  end

  private

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
