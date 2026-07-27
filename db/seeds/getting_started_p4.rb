# Reproducible seed: the "Getting start with P4" self-enrollment classroom
# and a progressive set of beginner exercises — a dummy's guide to P4.
#
#   bin/rails runner db/seeds/getting_started_p4.rb
#
# Idempotent: safe to re-run. Exercises are matched by their English title,
# so re-running updates content in place instead of duplicating. Owner is
# the first admin account in the current environment (works in dev & prod).
# Technical terms are intentionally kept in English in the pt-BR text.

owner = User.where(admin: true).order(:id).first
raise "No admin user found to own the exercises" unless owner

# ── Shared topology: two hosts around one BMv2 switch ───────────────────────
# host_ip / host_mac reused by the exercises' descriptions. Forwarding rules
# are per-exercise (only where the exercise defines a matching table).
def topology(rules)
  {
    "switch"      => { "name" => "sw1", "thrift_port" => 50001,
                       "image" => "ghcr.io/lucastrombet/p4ering/p4d:1.0" },
    "connections" => [
      { "port" => 1, "host_name" => "h1",
        "host_image" => "ghcr.io/lucastrombet/p4ering/net:1.0",
        "host_ip" => "10.0.1.2/24", "host_mac" => "00:00:00:00:01:02",
        "sw_ip" => "10.0.1.1/24", "sw_mac" => "00:00:00:00:01:01" },
      { "port" => 2, "host_name" => "h2",
        "host_image" => "ghcr.io/lucastrombet/p4ering/net:1.0",
        "host_ip" => "10.0.2.2/24", "host_mac" => "00:00:00:00:02:02",
        "sw_ip" => "10.0.2.1/24", "sw_mac" => "00:00:00:00:02:01" },
    ],
    "forwarding_rules" => rules,
    "traffic_test"     => { "from" => "h1", "command" => "ping -c 3 -W 2 10.0.2.2" },
  }.to_json
end

# The minimal v1model skeleton every exercise starts from. `ingress` is the
# body of MyIngress.apply that the student edits per exercise.
def skeleton(ingress)
  <<~P4
    /* -*- P4_16 -*- */
    #include <core.p4>
    #include <v1model.p4>

    const bit<16> TYPE_IPV4 = 0x800;

    header ethernet_t {
        bit<48> dstAddr;
        bit<48> srcAddr;
        bit<16> etherType;
    }

    header ipv4_t {
        bit<4>  version;
        bit<4>  ihl;
        bit<8>  diffserv;
        bit<16> totalLen;
        bit<16> identification;
        bit<3>  flags;
        bit<13> fragOffset;
        bit<8>  ttl;
        bit<8>  protocol;
        bit<16> hdrChecksum;
        bit<32> srcAddr;
        bit<32> dstAddr;
    }

    struct metadata { }
    struct headers {
        ethernet_t ethernet;
        ipv4_t     ipv4;
    }

    parser MyParser(packet_in packet, out headers hdr, inout metadata meta,
                    inout standard_metadata_t standard_metadata) {
        state start {
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

    control MyVerifyChecksum(inout headers hdr, inout metadata meta) { apply { } }

    control MyIngress(inout headers hdr, inout metadata meta,
                      inout standard_metadata_t standard_metadata) {
        action drop() { mark_to_drop(standard_metadata); }

    #{ingress}
    }

    control MyEgress(inout headers hdr, inout metadata meta,
                     inout standard_metadata_t standard_metadata) { apply { } }

    control MyComputeChecksum(inout headers hdr, inout metadata meta) {
        apply {
            update_checksum(
                hdr.ipv4.isValid(),
                { hdr.ipv4.version, hdr.ipv4.ihl, hdr.ipv4.diffserv,
                  hdr.ipv4.totalLen, hdr.ipv4.identification, hdr.ipv4.flags,
                  hdr.ipv4.fragOffset, hdr.ipv4.ttl, hdr.ipv4.protocol,
                  hdr.ipv4.srcAddr, hdr.ipv4.dstAddr },
                hdr.ipv4.hdrChecksum, HashAlgorithm.csum16);
        }
    }

    control MyDeparser(packet_out packet, in headers hdr) {
        apply {
            packet.emit(hdr.ethernet);
            packet.emit(hdr.ipv4);
        }
    }

    V1Switch(MyParser(), MyVerifyChecksum(), MyIngress(),
             MyEgress(), MyComputeChecksum(), MyDeparser()) main;
  P4
end

# ── The progression ─────────────────────────────────────────────────────────
# Each entry: en/pt title + description, difficulty, starter ingress body,
# and forwarding rules for its topology (empty unless it defines a table).
EXERCISES = [
  {
    en_title: "1 · Hello, P4!",
    pt_title: "1 · Olá, P4!",
    difficulty: 1,
    en_desc: <<~D.strip,
      Welcome to P4! Your first program does the simplest useful thing a switch can do: send every packet out of port 2.

      A P4 program is built from a parser, one or more controls (ingress/egress), and a deparser, wired together at the bottom by `V1Switch(...)`. For now you only touch the ingress `apply` block.

      **TODO:** inside `apply`, set `standard_metadata.egress_spec = 2;` so every packet leaves on port 2.
    D
    pt_desc: <<~D.strip,
      Bem-vindo ao P4! Seu primeiro programa faz a coisa útil mais simples que um switch pode fazer: enviar todo pacote pela porta 2.

      Um programa P4 é montado a partir de um parser, um ou mais controls (ingress/egress) e um deparser, conectados no final por `V1Switch(...)`. Por enquanto você só mexe no bloco `apply` do ingress.

      **TODO:** dentro do `apply`, defina `standard_metadata.egress_spec = 2;` para que todo pacote saia pela porta 2.
    D
    ingress: "    apply {\n        // TODO: send every packet out of port 2\n    }",
    rules: [],
  },
  {
    en_title: "2 · Send it back where it came from",
    pt_title: "2 · Devolva para a porta de origem",
    difficulty: 1,
    en_desc: <<~D.strip,
      The switch knows which port a packet arrived on: `standard_metadata.ingress_port`. Use it to build an "echo" switch that bounces every packet straight back out the port it came in.

      **TODO:** in `apply`, set `standard_metadata.egress_spec = standard_metadata.ingress_port;`.

      Concepts: `standard_metadata` carries per-packet state (ingress port, egress spec, timestamps, ...) that the P4 architecture fills in for you.
    D
    pt_desc: <<~D.strip,
      O switch sabe em qual porta um pacote chegou: `standard_metadata.ingress_port`. Use isso para construir um switch "eco", que devolve cada pacote pela mesma porta por onde ele entrou.

      **TODO:** no `apply`, defina `standard_metadata.egress_spec = standard_metadata.ingress_port;`.

      Conceitos: o `standard_metadata` carrega o estado por pacote (ingress port, egress spec, timestamps, ...) que a arquitetura P4 preenche para você.
    D
    ingress: "    apply {\n        // TODO: echo the packet back out its ingress port\n    }",
    rules: [],
  },
  {
    en_title: "3 · Drop everything",
    pt_title: "3 · Descarte tudo",
    difficulty: 1,
    en_desc: <<~D.strip,
      Sometimes the right action is to throw a packet away. The skeleton already defines a `drop()` action that calls the `mark_to_drop(standard_metadata)` primitive.

      **TODO:** call `drop();` inside `apply` so no packet is ever forwarded.

      When you run this, expect the traffic test (`ping`) to report 100% loss — that means your switch is dropping correctly, not that the exercise failed.
    D
    pt_desc: <<~D.strip,
      Às vezes a ação certa é jogar o pacote fora. O esqueleto já define uma action `drop()`, que chama o primitivo `mark_to_drop(standard_metadata)`.

      **TODO:** chame `drop();` dentro do `apply` para que nenhum pacote seja encaminhado.

      Ao executar, espere que o teste de tráfego (`ping`) reporte 100% de perda — isso significa que seu switch está descartando corretamente, e não que o exercício falhou.
    D
    ingress: "    apply {\n        // TODO: drop every packet\n    }",
    rules: [],
  },
  {
    en_title: "4 · Only forward IPv4",
    pt_title: "4 · Encaminhe apenas IPv4",
    difficulty: 1,
    en_desc: <<~D.strip,
      Real switches make decisions based on the packet's contents. A header is `valid` only if the parser extracted it. The parser here only extracts `ipv4` when the EtherType says so.

      **TODO:** in `apply`, forward out port 2 **only if** `hdr.ipv4.isValid()`; otherwise `drop()`.

      Concepts: `hdr.<name>.isValid()` tells you whether a header is present on this packet — the basis of every conditional in the data plane.
    D
    pt_desc: <<~D.strip,
      Switches reais tomam decisões com base no conteúdo do pacote. Um header é `valid` apenas se o parser o extraiu. O parser aqui só extrai o `ipv4` quando o EtherType indica isso.

      **TODO:** no `apply`, encaminhe pela porta 2 **somente se** `hdr.ipv4.isValid()`; caso contrário, `drop()`.

      Conceitos: `hdr.<nome>.isValid()` diz se um header está presente neste pacote — a base de toda decisão condicional no data plane.
    D
    ingress: "    apply {\n        // TODO: forward IPv4 packets out port 2, drop the rest\n    }",
    rules: [],
  },
  {
    en_title: "5 · Decrement the TTL",
    pt_title: "5 · Decremente o TTL",
    difficulty: 2,
    en_desc: <<~D.strip,
      Every router decrements the IPv4 Time To Live so packets can't loop forever. You can read and write header fields directly.

      **TODO:** when `hdr.ipv4.isValid()`, do `hdr.ipv4.ttl = hdr.ipv4.ttl - 1;` and forward out port 2.

      Note: after changing an IPv4 field the header checksum is stale — the skeleton's `MyComputeChecksum` already recomputes it for you, so receivers still accept the packet.
    D
    pt_desc: <<~D.strip,
      Todo roteador decrementa o Time To Live (TTL) do IPv4 para que pacotes não fiquem em loop para sempre. Você pode ler e escrever campos de header diretamente.

      **TODO:** quando `hdr.ipv4.isValid()`, faça `hdr.ipv4.ttl = hdr.ipv4.ttl - 1;` e encaminhe pela porta 2.

      Observação: depois de alterar um campo do IPv4, o checksum do header fica desatualizado — o `MyComputeChecksum` do esqueleto já o recalcula para você, então os receptores continuam aceitando o pacote.
    D
    ingress: "    apply {\n        // TODO: decrement hdr.ipv4.ttl and forward out port 2\n    }",
    rules: [],
  },
  {
    en_title: "6 · Your first match-action table",
    pt_title: "6 · Sua primeira tabela match-action",
    difficulty: 2,
    en_desc: <<~D.strip,
      Tables are the heart of P4. A table matches on a `key` and runs the chosen `action`. Instead of hard-coding the output port, let a table decide it based on the destination MAC.

      **TODO:**
      1. Declare an action `forward(bit<9> port)` that sets `standard_metadata.egress_spec = port;`
      2. Declare a table `dmac` with `key = { hdr.ethernet.dstAddr: exact; }`, `actions = { forward; drop; }`, and `default_action = drop();`
      3. In `apply`, call `dmac.apply();`

      The control plane fills the table at runtime — this exercise's rules send h1↔h2 by MAC.
    D
    pt_desc: <<~D.strip,
      Tabelas são o coração do P4. Uma tabela faz match em uma `key` e executa a `action` escolhida. Em vez de fixar a porta de saída no código, deixe uma tabela decidir com base no MAC de destino.

      **TODO:**
      1. Declare uma action `forward(bit<9> port)` que faça `standard_metadata.egress_spec = port;`
      2. Declare uma tabela `dmac` com `key = { hdr.ethernet.dstAddr: exact; }`, `actions = { forward; drop; }` e `default_action = drop();`
      3. No `apply`, chame `dmac.apply();`

      O control plane preenche a tabela em tempo de execução — as regras deste exercício conectam h1↔h2 por MAC.
    D
    ingress: "    // TODO: declare action forward(bit<9> port) and table dmac here\n\n    apply {\n        // TODO: apply the dmac table\n    }",
    rules: [
      "table_add MyIngress.dmac forward 00:00:00:00:02:02 => 2",
      "table_add MyIngress.dmac forward 00:00:00:00:01:02 => 1",
    ],
  },
  {
    en_title: "7 · Longest-prefix-match routing",
    pt_title: "7 · Roteamento por longest-prefix-match",
    difficulty: 2,
    en_desc: <<~D.strip,
      IP routing matches the destination address against a table of prefixes and picks the **longest** one that matches — an `lpm` key.

      **TODO:**
      1. Declare an action `ipv4_forward(bit<9> port)` that sets `standard_metadata.egress_spec = port;`
      2. Declare a table `ipv4_lpm` with `key = { hdr.ipv4.dstAddr: lpm; }`, `actions = { ipv4_forward; drop; }`, `default_action = drop();`
      3. In `apply`, apply the table only when `hdr.ipv4.isValid()`.

      Concepts: `lpm` is how routers scale — one prefix like `10.0.2.0/24` covers a whole subnet.
    D
    pt_desc: <<~D.strip,
      O roteamento IP faz match do endereço de destino contra uma tabela de prefixos e escolhe o **mais longo** que casa — uma key do tipo `lpm`.

      **TODO:**
      1. Declare uma action `ipv4_forward(bit<9> port)` que faça `standard_metadata.egress_spec = port;`
      2. Declare uma tabela `ipv4_lpm` com `key = { hdr.ipv4.dstAddr: lpm; }`, `actions = { ipv4_forward; drop; }`, `default_action = drop();`
      3. No `apply`, aplique a tabela somente quando `hdr.ipv4.isValid()`.

      Conceitos: o `lpm` é o que faz roteadores escalarem — um prefixo como `10.0.2.0/24` cobre uma sub-rede inteira.
    D
    ingress: "    // TODO: declare action ipv4_forward and table ipv4_lpm here\n\n    apply {\n        // TODO: apply ipv4_lpm when the IPv4 header is valid\n    }",
    rules: [
      "table_add MyIngress.ipv4_lpm ipv4_forward 10.0.2.2/32 => 2",
      "table_add MyIngress.ipv4_lpm ipv4_forward 10.0.1.2/32 => 1",
    ],
  },
  {
    en_title: "8 · Rewrite the MAC addresses",
    pt_title: "8 · Reescreva os endereços MAC",
    difficulty: 2,
    en_desc: <<~D.strip,
      A real router rewrites the Ethernet source/destination MACs at every hop: the new source is the router's port MAC, the new destination is the next hop's MAC.

      **TODO:** extend your `ipv4_forward` action to take a `bit<48> dstAddr` parameter and:
      - `hdr.ethernet.srcAddr = hdr.ethernet.dstAddr;`
      - `hdr.ethernet.dstAddr = dstAddr;`
      - `standard_metadata.egress_spec = port;`
      - `hdr.ipv4.ttl = hdr.ipv4.ttl - 1;`

      The table key stays `lpm` on `hdr.ipv4.dstAddr`.
    D
    pt_desc: <<~D.strip,
      Um roteador real reescreve os MACs de origem/destino do Ethernet a cada salto: a nova origem é o MAC da porta do roteador, o novo destino é o MAC do próximo salto.

      **TODO:** estenda sua action `ipv4_forward` para receber um parâmetro `bit<48> dstAddr` e:
      - `hdr.ethernet.srcAddr = hdr.ethernet.dstAddr;`
      - `hdr.ethernet.dstAddr = dstAddr;`
      - `standard_metadata.egress_spec = port;`
      - `hdr.ipv4.ttl = hdr.ipv4.ttl - 1;`

      A key da tabela continua `lpm` em `hdr.ipv4.dstAddr`.
    D
    ingress: "    // TODO: action ipv4_forward(bit<48> dstAddr, bit<9> port) + table ipv4_lpm\n\n    apply {\n        // TODO: apply ipv4_lpm when the IPv4 header is valid\n    }",
    rules: [
      "table_add MyIngress.ipv4_lpm ipv4_forward 10.0.2.2/32 => 00:00:00:00:02:02 2",
      "table_add MyIngress.ipv4_lpm ipv4_forward 10.0.1.2/32 => 00:00:00:00:01:02 1",
    ],
  },
  {
    en_title: "9 · A simple ACL (drop by source IP)",
    pt_title: "9 · Uma ACL simples (descarte por IP de origem)",
    difficulty: 2,
    en_desc: <<~D.strip,
      Access Control Lists let a switch filter traffic. Add a second table that runs **before** forwarding and drops packets from unwanted sources.

      **TODO:**
      1. Keep your `ipv4_lpm` table from the previous exercise.
      2. Add a table `acl` with `key = { hdr.ipv4.srcAddr: exact; }` and `actions = { drop; NoAction; }`, `default_action = NoAction();`
      3. In `apply`: when IPv4 is valid, first `acl.apply();`, then `ipv4_lpm.apply();`

      The control plane can then block any source with one rule — no recompile needed.
    D
    pt_desc: <<~D.strip,
      Access Control Lists (ACLs) permitem que um switch filtre tráfego. Adicione uma segunda tabela que roda **antes** do forwarding e descarta pacotes de origens indesejadas.

      **TODO:**
      1. Mantenha sua tabela `ipv4_lpm` do exercício anterior.
      2. Adicione uma tabela `acl` com `key = { hdr.ipv4.srcAddr: exact; }` e `actions = { drop; NoAction; }`, `default_action = NoAction();`
      3. No `apply`: quando o IPv4 for válido, primeiro `acl.apply();`, depois `ipv4_lpm.apply();`

      O control plane pode então bloquear qualquer origem com uma regra — sem recompilar.
    D
    ingress: "    // TODO: table acl (drop by srcAddr) + your ipv4_lpm table\n\n    apply {\n        // TODO: apply acl then ipv4_lpm when IPv4 is valid\n    }",
    rules: [
      "table_add MyIngress.ipv4_lpm ipv4_forward 10.0.2.2/32 => 00:00:00:00:02:02 2",
      "table_add MyIngress.ipv4_lpm ipv4_forward 10.0.1.2/32 => 00:00:00:00:01:02 1",
    ],
  },
  {
    en_title: "10 · Count the packets",
    pt_title: "10 · Conte os pacotes",
    difficulty: 2,
    en_desc: <<~D.strip,
      Switches keep statistics. A `counter` is stateful memory the data plane can increment as packets fly through.

      **TODO:**
      1. Declare `counter(2, CounterType.packets) port_counter;` inside `MyIngress`.
      2. Keep your `ipv4_lpm` forwarding from exercise 8.
      3. In `apply`, after forwarding, do `port_counter.count((bit<32>)standard_metadata.egress_spec);`

      Concepts: `counter`/`register` are how P4 remembers things across packets — the door to telemetry and stateful data planes.
    D
    pt_desc: <<~D.strip,
      Switches mantêm estatísticas. Um `counter` é uma memória com estado que o data plane pode incrementar conforme os pacotes passam.

      **TODO:**
      1. Declare `counter(2, CounterType.packets) port_counter;` dentro do `MyIngress`.
      2. Mantenha o forwarding `ipv4_lpm` do exercício 8.
      3. No `apply`, depois de encaminhar, faça `port_counter.count((bit<32>)standard_metadata.egress_spec);`

      Conceitos: `counter`/`register` são como o P4 lembra coisas entre pacotes — a porta de entrada para telemetria e data planes com estado.
    D
    ingress: "    counter(2, CounterType.packets) port_counter;\n\n    // TODO: action ipv4_forward + table ipv4_lpm (from exercise 8)\n\n    apply {\n        // TODO: apply ipv4_lpm, then count on egress_spec\n    }",
    rules: [
      "table_add MyIngress.ipv4_lpm ipv4_forward 10.0.2.2/32 => 00:00:00:00:02:02 2",
      "table_add MyIngress.ipv4_lpm ipv4_forward 10.0.1.2/32 => 00:00:00:00:01:02 1",
    ],
  },
  {
    en_title: "11 · Broadcast to every other port",
    pt_title: "11 · Broadcast para todas as outras portas",
    difficulty: 2,
    en_desc: <<~D.strip,
      When a switch doesn't know where a destination lives, it floods: send the packet out every port except the one it came in on. In v1model this is done with multicast groups.

      **TODO:** in `apply`, set `standard_metadata.mcast_grp = 1;`. The control plane maps group 1 to "all ports except ingress".

      Concepts: multicast/replication is how ARP, discovery, and unknown-unicast flooding work — one packet in, many out.
    D
    pt_desc: <<~D.strip,
      Quando um switch não sabe onde o destino está, ele faz flood: envia o pacote por todas as portas, exceto aquela por onde ele entrou. No v1model isso é feito com multicast groups.

      **TODO:** no `apply`, defina `standard_metadata.mcast_grp = 1;`. O control plane mapeia o grupo 1 para "todas as portas exceto a de ingresso".

      Conceitos: multicast/replicação é como funcionam ARP, discovery e o flooding de unknown-unicast — um pacote entra, vários saem.
    D
    ingress: "    apply {\n        // TODO: set the multicast group so the packet floods\n    }",
    rules: [],
  },
  {
    en_title: "12 · Putting it together: a tiny router",
    pt_title: "12 · Juntando tudo: um roteador em miniatura",
    difficulty: 2,
    en_desc: <<~D.strip,
      Graduation exercise — combine everything into a working IPv4 router: parse, filter, route, rewrite, decrement, checksum.

      **TODO:** in `apply`, when `hdr.ipv4.isValid()`:
      1. Run an `acl` table (drop by `srcAddr`).
      2. Run an `ipv4_lpm` table whose action rewrites both MACs, sets the port, and decrements the TTL.

      Everything else — parser, deparser, checksum — is already wired in the skeleton. If your captures show h2 receiving packets from h1 with a decremented TTL and rewritten MACs, you have built a real data-plane router. 🦈
    D
    pt_desc: <<~D.strip,
      Exercício de formatura — combine tudo em um roteador IPv4 funcional: parse, filtro, roteamento, reescrita, decremento, checksum.

      **TODO:** no `apply`, quando `hdr.ipv4.isValid()`:
      1. Rode uma tabela `acl` (descarte por `srcAddr`).
      2. Rode uma tabela `ipv4_lpm` cuja action reescreve os dois MACs, define a porta e decrementa o TTL.

      Todo o resto — parser, deparser, checksum — já está conectado no esqueleto. Se suas capturas mostrarem h2 recebendo pacotes de h1 com o TTL decrementado e os MACs reescritos, você construiu um roteador de data plane de verdade. 🦈
    D
    ingress: "    // TODO: acl table + ipv4_lpm table (rewrite MACs, set port, decrement TTL)\n\n    apply {\n        // TODO: acl then ipv4_lpm when IPv4 is valid\n    }",
    rules: [
      "table_add MyIngress.ipv4_lpm ipv4_forward 10.0.2.2/32 => 00:00:00:00:02:02 2",
      "table_add MyIngress.ipv4_lpm ipv4_forward 10.0.1.2/32 => 00:00:00:00:01:02 1",
    ],
  },
]

# ── Apply ───────────────────────────────────────────────────────────────────
ActiveRecord::Base.transaction do
  classroom = Classroom.find_or_initialize_by(name: "Getting start with P4")
  classroom.assign_attributes(
    professor:       owner,
    description:     "A beginner-friendly, self-paced introduction to P4 programming — " \
                     "from a pass-through switch to a working IPv4 router, one small step at a time.",
    start_date:      Date.current,
    end_date:        Date.current + 1.year,
    self_enrollment: true,
    date_enrollment: Date.current + 1.year,
  )
  classroom.save!

  EXERCISES.each do |data|
    ex = Exercise.find_or_initialize_by(title: data[:en_title])
    ex.assign_attributes(
      owner:                       owner,
      language:                    "P4",
      difficulty:                  data[:difficulty],
      restricted:                  false,
      visible_by_other_professors: true,
      title:                       data[:en_title],
      description:                 data[:en_desc],
      title_translations:          { "en" => data[:en_title], "pt-BR" => data[:pt_title] },
      description_translations:    { "en" => data[:en_desc],  "pt-BR" => data[:pt_desc] },
      starter_code:                skeleton(data[:ingress]),
      topology_config:             topology(data[:rules]),
      evaluation_criteria:         nil,
    )
    ex.save!

    unless classroom.classroom_exercises.exists?(exercise_id: ex.id)
      classroom.classroom_exercises.create!(
        exercise: ex, start_date: classroom.start_date, end_date: classroom.end_date
      )
    end
  end

  puts "Classroom '#{classroom.name}' — #{classroom.classroom_exercises.count} exercises, " \
       "self_enrollment=#{classroom.self_enrollment}, owner=#{owner.email}"
end
