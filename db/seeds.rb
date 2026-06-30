# Idempotent seed file — safe to run multiple times.
# Run manually:  bin/rails db:seed
# Run via setup: bin/rails db:setup  (create + schema + seed)

# ── Admin user ──────────────────────────────────────────────────────────────
admin = User.find_or_initialize_by(email: 'admin@p4ering.com')
if admin.new_record?
  admin.name                  = 'Administrator'
  admin.password              = 'admin123'
  admin.password_confirmation = 'admin123'
  admin.admin                 = true
  admin.save!
  puts "Created admin user: admin@p4ering.com / admin123"
else
  puts "Admin user already exists — skipping"
end

# ── Starter code skeletons (from https://github.com/p4lang/tutorials) ────────
BASIC_FORWARDING_SKELETON = <<~'P4'
  /* -*- P4_16 -*- */
  #include <core.p4>
  #include <v1model.p4>

  const bit<16> TYPE_IPV4 = 0x800;

  typedef bit<9>  egressSpec_t;
  typedef bit<48> macAddr_t;
  typedef bit<32> ip4Addr_t;

  header ethernet_t {
      macAddr_t dstAddr;
      macAddr_t srcAddr;
      bit<16>   etherType;
  }

  header ipv4_t {
      bit<4>    version;
      bit<4>    ihl;
      bit<8>    diffserv;
      bit<16>   totalLen;
      bit<16>   identification;
      bit<3>    flags;
      bit<13>   fragOffset;
      bit<8>    ttl;
      bit<8>    protocol;
      bit<16>   hdrChecksum;
      ip4Addr_t srcAddr;
      ip4Addr_t dstAddr;
  }

  struct metadata { /* empty */ }

  struct headers {
      ethernet_t ethernet;
      ipv4_t     ipv4;
  }

  // ── Parser ───────────────────────────────────────────────────────────────
  parser MyParser(packet_in packet,
                  out headers hdr,
                  inout metadata meta,
                  inout standard_metadata_t standard_metadata) {
      state start {
          // TODO: extract Ethernet, then branch on etherType
          transition accept;
      }
  }

  control MyVerifyChecksum(inout headers hdr, inout metadata meta) {
      apply { }
  }

  // ── Ingress ──────────────────────────────────────────────────────────────
  control MyIngress(inout headers hdr,
                    inout metadata meta,
                    inout standard_metadata_t standard_metadata) {

      action drop() {
          mark_to_drop(standard_metadata);
      }

      action ipv4_forward(macAddr_t dstAddr, egressSpec_t port) {
          // TODO: set egress port, update MAC addresses, decrement TTL
      }

      table ipv4_lpm {
          key     = { hdr.ipv4.dstAddr: lpm; }
          actions = { ipv4_forward; drop; NoAction; }
          size    = 1024;
          default_action = NoAction();
      }

      apply {
          // TODO: apply ipv4_lpm only when the IPv4 header is valid
          ipv4_lpm.apply();
      }
  }

  control MyEgress(inout headers hdr,
                   inout metadata meta,
                   inout standard_metadata_t standard_metadata) {
      apply { }
  }

  control MyComputeChecksum(inout headers hdr, inout metadata meta) {
      apply {
          update_checksum(
              hdr.ipv4.isValid(),
              { hdr.ipv4.version, hdr.ipv4.ihl, hdr.ipv4.diffserv,
                hdr.ipv4.totalLen, hdr.ipv4.identification,
                hdr.ipv4.flags, hdr.ipv4.fragOffset, hdr.ipv4.ttl,
                hdr.ipv4.protocol, hdr.ipv4.srcAddr, hdr.ipv4.dstAddr },
              hdr.ipv4.hdrChecksum,
              HashAlgorithm.csum16);
      }
  }

  // ── Deparser ─────────────────────────────────────────────────────────────
  control MyDeparser(packet_out packet, in headers hdr) {
      apply {
          // TODO: emit ethernet then ipv4
      }
  }

  V1Switch(
      MyParser(), MyVerifyChecksum(), MyIngress(),
      MyEgress(), MyComputeChecksum(), MyDeparser()
  ) main;
P4

BASIC_TUNNEL_SKELETON = <<~'P4'
  /* -*- P4_16 -*- */
  #include <core.p4>
  #include <v1model.p4>

  const bit<16> TYPE_MYTUNNEL = 0x1212;
  const bit<16> TYPE_IPV4     = 0x800;

  typedef bit<9>  egressSpec_t;
  typedef bit<48> macAddr_t;
  typedef bit<32> ip4Addr_t;

  header ethernet_t {
      macAddr_t dstAddr;
      macAddr_t srcAddr;
      bit<16>   etherType;
  }

  header myTunnel_t {
      bit<16> proto_id;
      bit<16> dst_id;
  }

  header ipv4_t {
      bit<4>    version;
      bit<4>    ihl;
      bit<8>    diffserv;
      bit<16>   totalLen;
      bit<16>   identification;
      bit<3>    flags;
      bit<13>   fragOffset;
      bit<8>    ttl;
      bit<8>    protocol;
      bit<16>   hdrChecksum;
      ip4Addr_t srcAddr;
      ip4Addr_t dstAddr;
  }

  struct metadata { /* empty */ }

  struct headers {
      ethernet_t ethernet;
      myTunnel_t myTunnel;
      ipv4_t     ipv4;
  }

  // ── Parser ───────────────────────────────────────────────────────────────
  // TODO: parse myTunnel header when etherType == TYPE_MYTUNNEL (0x1212),
  //       then conditionally parse IPv4 when proto_id == TYPE_IPV4
  parser MyParser(packet_in packet,
                  out headers hdr,
                  inout metadata meta,
                  inout standard_metadata_t standard_metadata) {
      state start { transition parse_ethernet; }

      state parse_ethernet {
          packet.extract(hdr.ethernet);
          transition select(hdr.ethernet.etherType) {
              TYPE_IPV4: parse_ipv4;
              default:   accept;
          }
      }

      state parse_ipv4 {
          packet.extract(hdr.ipv4);
          transition accept;
      }
  }

  control MyVerifyChecksum(inout headers hdr, inout metadata meta) {
      apply { }
  }

  // ── Ingress ──────────────────────────────────────────────────────────────
  control MyIngress(inout headers hdr,
                    inout metadata meta,
                    inout standard_metadata_t standard_metadata) {

      action drop() { mark_to_drop(standard_metadata); }

      action ipv4_forward(macAddr_t dstAddr, egressSpec_t port) {
          standard_metadata.egress_spec = port;
          hdr.ethernet.srcAddr = hdr.ethernet.dstAddr;
          hdr.ethernet.dstAddr = dstAddr;
          hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
      }

      table ipv4_lpm {
          key     = { hdr.ipv4.dstAddr: lpm; }
          actions = { ipv4_forward; drop; NoAction; }
          size    = 1024;
          default_action = drop();
      }

      // TODO: declare action myTunnel_forward(egressSpec_t port)
      // TODO: declare table myTunnel_exact matching on myTunnel.dst_id (exact)

      apply {
          // TODO: if tunnel header is valid apply myTunnel_exact,
          //       otherwise fall through to ipv4_lpm
          if (hdr.ipv4.isValid()) {
              ipv4_lpm.apply();
          }
      }
  }

  control MyEgress(inout headers hdr,
                   inout metadata meta,
                   inout standard_metadata_t standard_metadata) {
      apply { }
  }

  control MyComputeChecksum(inout headers hdr, inout metadata meta) {
      apply {
          update_checksum(
              hdr.ipv4.isValid(),
              { hdr.ipv4.version, hdr.ipv4.ihl, hdr.ipv4.diffserv,
                hdr.ipv4.totalLen, hdr.ipv4.identification,
                hdr.ipv4.flags, hdr.ipv4.fragOffset, hdr.ipv4.ttl,
                hdr.ipv4.protocol, hdr.ipv4.srcAddr, hdr.ipv4.dstAddr },
              hdr.ipv4.hdrChecksum,
              HashAlgorithm.csum16);
      }
  }

  // ── Deparser ─────────────────────────────────────────────────────────────
  control MyDeparser(packet_out packet, in headers hdr) {
      apply {
          packet.emit(hdr.ethernet);
          // TODO: emit myTunnel header
          packet.emit(hdr.ipv4);
      }
  }

  V1Switch(
      MyParser(), MyVerifyChecksum(), MyIngress(),
      MyEgress(), MyComputeChecksum(), MyDeparser()
  ) main;
P4

SOURCE_ROUTING_SKELETON = <<~'P4'
  /* -*- P4_16 -*- */
  #include <core.p4>
  #include <v1model.p4>

  const bit<16> TYPE_IPV4       = 0x800;
  const bit<16> TYPE_SRCROUTING = 0x1234;

  #define MAX_HOPS 9

  typedef bit<9>  egressSpec_t;
  typedef bit<48> macAddr_t;
  typedef bit<32> ip4Addr_t;

  header ethernet_t {
      macAddr_t dstAddr;
      macAddr_t srcAddr;
      bit<16>   etherType;
  }

  header srcRoute_t {
      bit<1>  bos;   // bottom-of-stack flag
      bit<15> port;  // output port for this hop
  }

  header ipv4_t {
      bit<4>    version;
      bit<4>    ihl;
      bit<8>    diffserv;
      bit<16>   totalLen;
      bit<16>   identification;
      bit<3>    flags;
      bit<13>   fragOffset;
      bit<8>    ttl;
      bit<8>    protocol;
      bit<16>   hdrChecksum;
      ip4Addr_t srcAddr;
      ip4Addr_t dstAddr;
  }

  struct metadata { /* empty */ }

  struct headers {
      ethernet_t           ethernet;
      srcRoute_t[MAX_HOPS] srcRoutes;
      ipv4_t               ipv4;
  }

  // ── Parser ───────────────────────────────────────────────────────────────
  parser MyParser(packet_in packet,
                  out headers hdr,
                  inout metadata meta,
                  inout standard_metadata_t standard_metadata) {

      state start { transition parse_ethernet; }

      state parse_ethernet {
          packet.extract(hdr.ethernet);
          // TODO: transition to parse_srcRouting when etherType == TYPE_SRCROUTING
          transition accept;
      }

      state parse_srcRouting {
          // TODO: extract next srcRoutes entry;
          //       loop while bos == 0, then transition to parse_ipv4
          transition accept;
      }

      state parse_ipv4 {
          packet.extract(hdr.ipv4);
          transition accept;
      }
  }

  control MyVerifyChecksum(inout headers hdr, inout metadata meta) {
      apply { }
  }

  // ── Ingress ──────────────────────────────────────────────────────────────
  control MyIngress(inout headers hdr,
                    inout metadata meta,
                    inout standard_metadata_t standard_metadata) {

      action drop() { mark_to_drop(standard_metadata); }

      action srcRoute_nhop() {
          // TODO: set standard_metadata.egress_spec from hdr.srcRoutes[0].port
          //       and pop the top entry: hdr.srcRoutes.pop_front(1)
      }

      action srcRoute_finish() {
          hdr.ethernet.etherType = TYPE_IPV4;
      }

      action update_ttl() {
          hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
      }

      apply {
          if (hdr.srcRoutes[0].isValid()) {
              // TODO: if this is the last hop (bos == 1) call srcRoute_finish()
              // TODO: call srcRoute_nhop() to forward and pop the stack
              if (hdr.ipv4.isValid()) { update_ttl(); }
          } else {
              drop();
          }
      }
  }

  control MyEgress(inout headers hdr,
                   inout metadata meta,
                   inout standard_metadata_t standard_metadata) {
      apply { }
  }

  control MyComputeChecksum(inout headers hdr, inout metadata meta) {
      apply { }
  }

  // ── Deparser ─────────────────────────────────────────────────────────────
  control MyDeparser(packet_out packet, in headers hdr) {
      apply {
          packet.emit(hdr.ethernet);
          packet.emit(hdr.srcRoutes);
          packet.emit(hdr.ipv4);
      }
  }

  V1Switch(
      MyParser(), MyVerifyChecksum(), MyIngress(),
      MyEgress(), MyComputeChecksum(), MyDeparser()
  ) main;
P4

# ── Topology configs (P4Docker connection model) ─────────────────────────────
BASIC_FORWARDING_TOPOLOGY = JSON.generate(
  switch: {
    name:        "sw1",
    thrift_port: 50001,
    image:       "dnredson/p4d"
  },
  connections: [
    {
      port:       1,
      host_name:  "h1",
      host_image: "dnredson/net",
      host_ip:    "10.0.1.2/24",
      host_mac:   "00:00:00:00:01:02",
      sw_ip:      "10.0.1.1/24",
      sw_mac:     "00:00:00:00:01:01"
    },
    {
      port:       2,
      host_name:  "h2",
      host_image: "dnredson/net",
      host_ip:    "10.0.2.2/24",
      host_mac:   "00:00:00:00:02:02",
      sw_ip:      "10.0.2.1/24",
      sw_mac:     "00:00:00:00:02:01"
    }
  ],
  forwarding_rules: [
    "table_add MyIngress.ipv4_lpm ipv4_forward 10.0.1.2 => 00:00:00:00:01:02 1",
    "table_add MyIngress.ipv4_lpm ipv4_forward 10.0.2.2 => 00:00:00:00:02:02 2"
  ],
  traffic_test: {
    from:    "h1",
    command: "ping -c 3 -W 2 10.0.2.2"
  }
)

# ── P4 Exercises ─────────────────────────────────────────────────────────────
p4_exercises = [
  {
    title:           "Basic Forwarding",
    difficulty:      2,
    starter_code:    BASIC_FORWARDING_SKELETON,
    topology_config: BASIC_FORWARDING_TOPOLOGY,
    description:     <<~DESC
      Implement Layer 3 IPv4 forwarding on a BMv2 software switch.

      Complete the skeleton P4 program so that the switch forwards IPv4 packets by:

      1. Parsing Ethernet and IPv4 headers from incoming packets
      2. Looking up the destination IP address in an LPM table (ipv4_lpm)
      3. Calling ipv4_forward to set the output port, update source/destination MACs, and decrement the TTL
      4. Deparsing the headers back onto the outgoing packet in the correct order

      The skeleton already defines the header types, metadata struct, and the table/action signatures. Complete the 4 TODO sections marked in the starter code.

      Reference: https://github.com/p4lang/tutorials/tree/master/exercises/basic
    DESC
  },
  {
    title:        "Basic Tunneling",
    difficulty:   3,
    starter_code: BASIC_TUNNEL_SKELETON,
    description:  <<~DESC
      Extend an existing IPv4 router to support a custom tunneling protocol.

      When a packet arrives with EtherType 0x1212 (TYPE_MYTUNNEL), the switch must forward it based on the myTunnel header's dst_id field instead of the IP destination address. When proto_id inside myTunnel equals 0x0800 the inner IPv4 header should also be parsed.

      Complete the 4 TODO sections in the starter code:

      1. Update the parser to extract myTunnel when EtherType == 0x1212, then conditionally parse IPv4
      2. Declare the myTunnel_forward action that sets egress_spec from a control-plane parameter
      3. Declare the myTunnel_exact table doing exact matching on myTunnel.dst_id
      4. Update the ingress apply block: route via myTunnel_exact when the tunnel header is valid, fall through to ipv4_lpm otherwise
      5. Emit the myTunnel header in the deparser

      Reference: https://github.com/p4lang/tutorials/tree/master/exercises/basic_tunnel
    DESC
  },
  {
    title:        "Source Routing",
    difficulty:   4,
    starter_code: SOURCE_ROUTING_SKELETON,
    description:  <<~DESC
      Implement source routing: the sending host encodes the full forwarding path as a stack of port numbers embedded in the packet header. Each switch pops one entry and forwards to that port.

      The srcRoute_t header has two fields: bos (1-bit bottom-of-stack flag) and port (15-bit output port). Up to 9 hops are supported (MAX_HOPS = 9).

      Complete the 3 TODO sections in the starter code:

      1. Parser: transition to parse_srcRouting when EtherType == 0x1234; loop extracting srcRoutes entries until bos == 1, then parse IPv4
      2. srcRoute_nhop action: set standard_metadata.egress_spec from hdr.srcRoutes[0].port and pop the top entry with hdr.srcRoutes.pop_front(1)
      3. Apply block: call srcRoute_finish() (restore EtherType to IPv4) when bos == 1, then call srcRoute_nhop()

      Test by sending a packet with a port sequence such as [2, 3, 2, 1] through a 3-switch triangle topology and verifying it arrives at the correct host.

      Reference: https://github.com/p4lang/tutorials/tree/master/exercises/source_routing
    DESC
  }
]

p4_exercises.each do |attrs|
  ex = Exercise.find_or_initialize_by(title: attrs[:title])
  ex.language        = 'P4'
  ex.difficulty      = attrs[:difficulty]
  ex.description     = attrs[:description].strip
  ex.starter_code    = attrs[:starter_code].strip
  ex.topology_config = attrs[:topology_config]
  if ex.new_record?
    ex.save!
    puts "Created exercise: #{attrs[:title]}"
  elsif ex.changed?
    ex.save!
    puts "Updated exercise: #{attrs[:title]}"
  else
    puts "Exercise '#{attrs[:title]}' unchanged — skipping"
  end
end

# ── Traffic Generators ───────────────────────────────────────────────────────
traffic_generators = [
  {
    name:             'TCP Baseline',
    description:      'Fluxo TCP simples para verificar conectividade e throughput básico.',
    protocol:         'TCP',
    duration:         10,
    port:             5201,
    bandwidth:        nil,
    parallel_streams: 1,
    packet_length:    nil,
    interval:         1,
    reverse:          false,
    tos:              nil
  },
  {
    name:             'UDP Video Stream',
    description:      'Simula tráfego de vídeo com taxa constante de 5 Mbps via UDP.',
    protocol:         'UDP',
    duration:         30,
    port:             5201,
    bandwidth:        '5M',
    parallel_streams: 1,
    packet_length:    '1400',
    interval:         1,
    reverse:          false,
    tos:              nil
  },
  {
    name:             'TCP High Bandwidth',
    description:      'Teste de alta carga com 4 streams TCP paralelos para saturar o pipeline.',
    protocol:         'TCP',
    duration:         30,
    port:             5201,
    bandwidth:        '100M',
    parallel_streams: 4,
    packet_length:    nil,
    interval:         5,
    reverse:          false,
    tos:              nil
  },
  {
    name:             'UDP DSCP AF11',
    description:      'Tráfego UDP com marcação DSCP AF11 (0x28) para testar QoS no plano de dados.',
    protocol:         'UDP',
    duration:         20,
    port:             5201,
    bandwidth:        '10M',
    parallel_streams: 1,
    packet_length:    '512',
    interval:         1,
    reverse:          false,
    tos:              '0x28'
  }
]

traffic_generators.each do |attrs|
  tg = TrafficGenerator.find_or_initialize_by(name: attrs[:name])
  tg.assign_attributes(attrs)
  if tg.new_record?
    tg.save!
    puts "Created traffic generator: #{attrs[:name]}"
  elsif tg.changed?
    tg.save!
    puts "Updated traffic generator: #{attrs[:name]}"
  else
    puts "Traffic generator '#{attrs[:name]}' unchanged — skipping"
  end
end

# ── Packet Spoofing exercise ──────────────────────────────────────────────────
PACKET_SPOOFING_SKELETON = <<~'P4'
  /* -*- P4_16 -*- */
  #include <core.p4>
  #include <v1model.p4>

  typedef bit<9>  egressSpec_t;
  typedef bit<48> macAddr_t;
  typedef bit<32> ip4Addr_t;

  header ethernet_t {
      macAddr_t dstAddr;
      macAddr_t srcAddr;
      bit<16>   etherType;
  }

  header ipv4_t {
      bit<4>    version;
      bit<4>    ihl;
      bit<8>    diffserv;
      bit<16>   totalLen;
      bit<16>   identification;
      bit<3>    flags;
      bit<13>   fragOffset;
      bit<8>    ttl;
      bit<8>    protocol;
      bit<16>   hdrChecksum;
      ip4Addr_t srcAddr;
      ip4Addr_t dstAddr;
  }

  struct metadata_t {}

  struct headers_t {
      ethernet_t ethernet;
      ipv4_t     ipv4;
  }

  // ── Parser ───────────────────────────────────────────────────────────────
  parser MyParser(packet_in packet,
                  out headers_t hdr,
                  inout metadata_t meta,
                  inout standard_metadata_t standard_metadata) {
      state start {
          packet.extract(hdr.ethernet);
          transition select(hdr.ethernet.etherType) {
              0x0800: parse_ipv4;
              default: accept;
          }
      }
      state parse_ipv4 {
          packet.extract(hdr.ipv4);
          transition accept;
      }
  }

  control MyVerifyChecksum(inout headers_t hdr, inout metadata_t meta) {
      apply { }
  }

  // ── Ingress ──────────────────────────────────────────────────────────────
  control MyIngress(inout headers_t hdr,
                    inout metadata_t meta,
                    inout standard_metadata_t standard_metadata) {

      action drop() {
          mark_to_drop(standard_metadata);
      }

      // Rewrite dst IP and dst MAC, then forward out the given port.
      // Implements DNAT: packets aimed at h2 (10.0.1.2) are redirected to h3.
      action rewrite_and_forward(ip4Addr_t new_dst_ip, macAddr_t new_dst_mac, egressSpec_t port) {
          hdr.ipv4.dstAddr              = new_dst_ip;
          hdr.ethernet.dstAddr          = new_dst_mac;
          standard_metadata.egress_spec = port;
          hdr.ipv4.ttl                  = hdr.ipv4.ttl - 1;
      }

      // Forward without IP rewrite — used for return traffic (h3 → h1).
      action just_forward(macAddr_t dst_mac, egressSpec_t port) {
          hdr.ethernet.dstAddr          = dst_mac;
          standard_metadata.egress_spec = port;
          hdr.ipv4.ttl                  = hdr.ipv4.ttl - 1;
      }

      table routing {
          key = { hdr.ipv4.dstAddr: lpm; }
          actions = { rewrite_and_forward; just_forward; drop; }
          default_action = drop();
      }

      apply {
          if (hdr.ipv4.isValid()) {
              routing.apply();
          }
      }
  }

  control MyEgress(inout headers_t hdr,
                   inout metadata_t meta,
                   inout standard_metadata_t standard_metadata) {
      apply { }
  }

  control MyComputeChecksum(inout headers_t hdr, inout metadata_t meta) {
      apply {
          update_checksum(
              hdr.ipv4.isValid(),
              { hdr.ipv4.version, hdr.ipv4.ihl, hdr.ipv4.diffserv,
                hdr.ipv4.totalLen, hdr.ipv4.identification,
                hdr.ipv4.flags, hdr.ipv4.fragOffset, hdr.ipv4.ttl,
                hdr.ipv4.protocol, hdr.ipv4.srcAddr, hdr.ipv4.dstAddr },
              hdr.ipv4.hdrChecksum,
              HashAlgorithm.csum16);
      }
  }

  // ── Deparser ─────────────────────────────────────────────────────────────
  control MyDeparser(packet_out packet, in headers_t hdr) {
      apply {
          packet.emit(hdr.ethernet);
          packet.emit(hdr.ipv4);
      }
  }

  V1Switch(
      MyParser(), MyVerifyChecksum(), MyIngress(),
      MyEgress(), MyComputeChecksum(), MyDeparser()
  ) main;
P4

PACKET_SPOOFING_TOPOLOGY = JSON.generate(
  switch: {
    name:        "sw1",
    thrift_port: 50001,
    image:       "dnredson/p4d"
  },
  connections: [
    {
      port:       1,
      host_name:  "h1",
      host_image: "dnredson/net",
      host_ip:    "10.0.1.1/24",
      host_mac:   "08:00:00:01:01:01",
      sw_ip:      "10.0.1.254/24",
      sw_mac:     "08:00:00:01:00:01"
    },
    {
      port:       2,
      host_name:  "h2",
      host_image: "dnredson/net",
      host_ip:    "10.0.1.2/24",
      host_mac:   "08:00:00:01:01:02",
      sw_ip:      "10.0.1.253/24",
      sw_mac:     "08:00:00:01:00:02"
    },
    {
      port:       3,
      host_name:  "h3",
      host_image: "dnredson/net",
      host_ip:    "10.0.2.1/24",
      host_mac:   "08:00:00:02:01:01",
      sw_ip:      "10.0.2.254/24",
      sw_mac:     "08:00:00:02:00:01"
    }
  ],
  forwarding_rules: [
    "table_add MyIngress.routing rewrite_and_forward 10.0.1.2/32 => 0x0a000201 08:00:00:02:01:01 3",
    "table_add MyIngress.routing just_forward 10.0.1.1/32 => 08:00:00:01:01:01 1"
  ],
  traffic_test: {
    from:    "h1",
    command: "ping -c 3 -W 2 10.0.1.2"
  }
)

ex = Exercise.find_or_initialize_by(title: "Packet Spoofing")
ex.language        = "P4"
ex.difficulty      = 3
ex.starter_code    = PACKET_SPOOFING_SKELETON.strip
ex.topology_config = PACKET_SPOOFING_TOPOLOGY
ex.description     = <<~DESC.strip
  Packet Spoofing (Destination NAT) demonstrates how a P4 switch can transparently
  redirect traffic by rewriting IP and MAC headers entirely in the data plane.

  Topology — three hosts, one switch:
    h1  10.0.1.1/24  →  sw1 port 1   (traffic source / generator)
    h2  10.0.1.2/24  →  sw1 port 2   (spoofed destination)
    h3  10.0.2.1/24  →  sw1 port 3   (real delivery target)

  h1 sends ICMP packets addressed to h2 (10.0.1.2). The switch intercepts every
  such packet and applies DNAT via the routing table:
    • dst IP  is rewritten  10.0.1.2  →  10.0.2.1
    • dst MAC is rewritten  h2's MAC  →  h3's MAC (08:00:00:02:01:01)
    • packet  is forwarded  out port 3 toward h3

  h3 receives the spoofed packet with its own IP as destination and replies to
  h1's source address. The return path uses a second rule that forwards h1-bound
  traffic from port 3 back out port 1 without any IP rewrite.

  The IPv4 checksum is recomputed after every DNAT rewrite so receiving hosts
  accept the modified packet without errors.

  Forwarding rules loaded at runtime:
    table_add MyIngress.routing rewrite_and_forward 10.0.1.2/32 => 0x0a000201 08:00:00:02:01:01 3
    table_add MyIngress.routing just_forward        10.0.1.1/32 => 08:00:00:01:01:01 1

  Traffic test: ping -c 3 -W 2 10.0.1.2 from h1.
  A correct implementation shows replies arriving from 10.0.2.1 (h3), confirming
  that the switch transparently redirected every flow without h2 ever seeing a packet.
DESC

if ex.new_record?
  ex.save!
  puts "Created exercise: Packet Spoofing"
elsif ex.changed?
  ex.save!
  puts "Updated exercise: Packet Spoofing"
else
  puts "Exercise 'Packet Spoofing' unchanged — skipping"
end

puts "Seed completed!"
