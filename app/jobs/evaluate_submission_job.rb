require 'open3'
require 'timeout'
require 'json'
require 'net/http'
require 'uri'

class EvaluateSubmissionJob < ApplicationJob
  queue_as :default

  P4C_IMAGE = 'ghcr.io/lucastrombet/p4ering/p4c:1.0'

  COMPILE_TIMEOUT  = 30
  TOPOLOGY_TIMEOUT = 90   # seconds the topology containers stay alive
  TRAFFIC_TIMEOUT  = 20   # seconds allowed for the traffic_test command

  EXEC_INTERNAL_TOKEN = ENV.fetch('P4EXEC_INTERNAL_TOKEN', 'p4exec-dev-token')

  # Read at job-run time so development.rb ||= assignments take effect.
  def exec_service_url = ENV['P4EXEC_SERVICE_URL']

  def perform(submission_id)
    submission = Submission.find_by(id: submission_id)
    return unless submission

    submission.update!(status: 'evaluating')

    unless submission.exercise.language == 'P4'
      submission.update!(status: 'failed',
        feedback: "Sandbox only supports P4 exercises. Got: #{submission.exercise.language}")
      return
    end

    if exec_service_url.present?
      delegate_to_exec_service(submission)
    else
      run_p4_sandbox(submission)
    end
  rescue => e
    submission&.update(status: 'failed', feedback: "Sandbox error: #{e.message}")
  end

  private

  # ── Execution service delegation (Phase A+) ────────────────────────────────

  def delegate_to_exec_service(submission)
    job_id       = "p4t_#{submission.id}"
    callback_url = Rails.application.routes.url_helpers
                        .internal_exec_callback_url(
                          host:     ENV.fetch('RAILS_CALLBACK_HOST', 'localhost:3000'),
                          protocol: 'http'
                        )

    body = {
      job_id:       job_id,
      callback_url: callback_url,
      code:         submission.code,
      topology:     topology_with_traffic_tests(submission.exercise)
    }.to_json

    uri  = URI("#{exec_service_url}/execute")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 5
    http.read_timeout = 10

    req = Net::HTTP::Post.new(uri.path, {
      'Content-Type'      => 'application/json',
      'X-Internal-Token'  => EXEC_INTERNAL_TOKEN
    })
    req.body = body

    resp = http.request(req)

    unless resp.code.to_i == 202
      raise "Execution service returned HTTP #{resp.code}: #{resp.body}"
    end

    Rails.logger.info("[p4exec] Job #{job_id} accepted by execution service")
    # Result will arrive asynchronously via POST /internal/exec_callback
  end

  # The exercise's traffic-generator mappings, rendered into concrete
  # commands and injected as `traffic_tests` alongside the topology's own
  # legacy `traffic_test` (which p4exec still runs first if present). Both
  # commands are built here so p4exec stays a dumb executor with no iperf
  # knowledge: the one-shot server (-1) on the target host, and the client
  # on the source host aimed at the target's topology IP.
  def topology_with_traffic_tests(exercise)
    topo = exercise.parsed_topology
    return topo unless topo

    host_ips = (topo['connections'] || []).to_h do |c|
      [c['host_name'], c['host_ip'].to_s.split('/').first]
    end

    tests = exercise.exercise_traffic_generators.includes(:traffic_generator).filter_map do |m|
      gen       = m.traffic_generator
      target_ip = host_ips[m.to_host]
      next if target_ip.blank?

      {
        'from'           => m.from_host,
        'to'             => m.to_host,
        'label'          => "#{gen.name} (#{m.from_host} -> #{m.to_host})",
        'server_command' => "iperf3 -s -p #{gen.port} -1",
        'client_command' => gen.to_iperf_command(target_ip)
      }
    end

    tests.any? ? topo.merge('traffic_tests' => tests) : topo
  end

  private

  # ── Entry point ────────────────────────────────────────────────────────────

  def run_p4_sandbox(submission)
    Dir.mktmpdir("p4_#{submission.id}_") do |dir|
      src_dir = File.join(dir, 'src')
      out_dir = File.join(dir, 'out')
      FileUtils.mkdir_p([src_dir, out_dir])
      File.write(File.join(src_dir, 'program.p4'), submission.code)

      compile_ok, compile_log = compile_p4(src_dir, out_dir)
      unless compile_ok
        submission.update!(status: 'failed', feedback: section('Compilation failed', compile_log))
        return
      end

      json_path = Dir.glob(File.join(out_dir, '*.json')).first
      if json_path.nil?
        submission.update!(status: 'failed',
          feedback: section('Compilation failed',
            "Compiler exited cleanly but produced no JSON output.\n#{compile_log}"))
        return
      end

      json_name = File.basename(json_path)
      topology  = submission.exercise.topology_config

      if topology.present?
        result = run_topology_sandbox(submission.id, out_dir, json_name, topology)
        submission.update!(
          status:           'completed',
          feedback:         build_topology_feedback(compile_log, result),
          packet_captures:  result[:packet_captures]&.to_json
        )
      else
        switch_log = run_switch_only(out_dir, json_name)
        submission.update!(status: 'completed',
          feedback: build_feedback(compile_log, switch_log))
      end
    end
  end

  # ── Phase 1: compile ───────────────────────────────────────────────────────

  def compile_p4(src_dir, out_dir)
    _stdout, stderr, status = Timeout.timeout(COMPILE_TIMEOUT) do
      Open3.capture3(
        'docker', 'run', '--rm',
        '--network=none', '--memory=128m', '--cpus=0.5',
        '-v', "#{src_dir}:/src:ro",
        '-v', "#{out_dir}:/out",
        P4C_IMAGE,
        'p4c', '--target', 'bmv2', '--arch', 'v1model',
        '-o', '/out', '/src/program.p4'
      )
    end
    [status.success?, stderr.strip]
  rescue Timeout::Error
    [false, "Compilation timed out after #{COMPILE_TIMEOUT}s."]
  end

  # Phase 1 fallback — boot switch briefly to check it loads
  def run_switch_only(out_dir, json_name)
    timeout = 10
    stdout, stderr, _status = Timeout.timeout(timeout + 5) do
      Open3.capture3(
        'docker', 'run', '--rm',
        '--network=none', '--memory=128m', '--cpus=0.5',
        '-v', "#{out_dir}:/workspace:ro",
        'ghcr.io/lucastrombet/p4ering/behavioral-model:1.0',
        'timeout', timeout.to_s,
        'simple_switch', '--log-console', '--log-level', 'info',
        "/workspace/#{json_name}"
      )
    end
    (stderr.presence || stdout).strip
  rescue Timeout::Error
    "Switch boot timed out."
  end

  # ── Phase 2: P4Docker topology execution ──────────────────────────────────
  #
  # JSON format (matches P4Docker connection model):
  # {
  #   "switch":  { "name": "sw1", "thrift_port": 50001, "image": "dnredson/p4d" },
  #   "connections": [
  #     { "port": 1, "host_name": "h1", "host_image": "dnredson/net",
  #       "host_ip": "10.0.1.2/24", "host_mac": "00:00:00:00:01:02",
  #       "sw_ip":   "10.0.1.1/24", "sw_mac":   "00:00:00:00:01:01" },
  #     ...
  #   ],
  #   "forwarding_rules": ["table_add MyIngress.ipv4_lpm ipv4_forward ..."],
  #   "traffic_test": { "from": "h1", "command": "ping -c 3 -W 2 10.0.2.2" }
  # }
  def run_topology_sandbox(sub_id, out_dir, json_name, topology_json)
    topo   = JSON.parse(topology_json)
    sw     = topo['switch']
    conns  = topo['connections'] || []
    prefix = "p4t#{sub_id}"

    containers = []
    host_pids  = {}
    sw_pid     = nil
    result     = {}

    begin
      # ── Start host containers (one per unique host_name) ───────────────
      conns.each do |conn|
        name  = conn['host_name']
        cname = "#{prefix}_#{name}"
        next if containers.include?(cname)

        containers << cname
        capture3!('docker', 'run', '-itd', '--name', cname, '--rm',
                  '--network', 'none', '--privileged',
                  '-v', "shared:/codes", '--workdir', '/codes',
                  conn['host_image'] || 'ghcr.io/lucastrombet/p4ering/net:1.0')
        host_pids[name] = container_pid(cname)
      end

      # ── Start switch container ─────────────────────────────────────────
      sw_cname     = "#{prefix}_#{sw['name']}"
      sw_image     = sw['image'] || 'ghcr.io/lucastrombet/p4ering/p4d:1.0'
      thrift_port  = (sw['thrift_port'] || 50001).to_i
      containers  << sw_cname
      capture3!('docker', 'run', '-itd', '--name', sw_cname, '--rm',
                '--network', 'none', '--privileged',
                '-v', "shared:/codes", '--workdir', '/codes',
                '-v', "#{out_dir}:/workspace",
                sw_image)
      sw_pid = container_pid(sw_cname)

      # ── Wire veth pairs ────────────────────────────────────────────────
      conns.each do |conn|
        port      = conn['port'].to_i
        host_name = conn['host_name']
        host_pid  = host_pids[host_name]

        # Interface names ≤15 chars
        veth_sw = "#{prefix}s#{port}"[0, 15]
        veth_h  = "#{prefix}h#{port}"[0, 15]

        capture3!('ip', 'link', 'add', veth_sw, 'type', 'veth', 'peer', 'name', veth_h)

        # Move into namespaces
        capture3!('ip', 'link', 'set', veth_sw, 'netns', sw_pid)
        capture3!('ip', 'link', 'set', veth_h,  'netns', host_pid)

        # ── Switch side: rename → eth{port}, assign IP/MAC, promisc ─────
        sw_iface = "eth#{port}"
        netns_exec(sw_pid, 'ip', 'link', 'set', veth_sw, 'name', sw_iface)
        netns_exec(sw_pid, 'ip', 'link', 'set', sw_iface, 'address', conn['sw_mac'])
        netns_exec(sw_pid, 'ip', 'addr', 'add', conn['sw_ip'], 'dev', sw_iface)
        netns_exec(sw_pid, 'ip', 'link', 'set', sw_iface, 'up')
        netns_exec(sw_pid, 'ip', 'link', 'set', sw_iface, 'promisc', 'on')

        # ── Host side: rename → p4eth1, assign IP/MAC, promisc ──────────
        netns_exec(host_pid, 'ip', 'link', 'set', veth_h, 'name', 'p4eth1')
        netns_exec(host_pid, 'ip', 'link', 'set', 'p4eth1', 'address', conn['host_mac'])
        netns_exec(host_pid, 'ip', 'addr', 'add', conn['host_ip'], 'dev', 'p4eth1')
        netns_exec(host_pid, 'ip', 'link', 'set', 'p4eth1', 'up')

        # Promiscuous + disable TX checksum offload (mirrors P4Docker's 1SWCP.sh)
        capture3!('docker', 'exec', "#{prefix}_#{host_name}",
                  'ip', 'link', 'set', 'p4eth1', 'promisc', 'on')
        capture3!('docker', 'exec', "#{prefix}_#{host_name}",
                  'sh', '-c', 'ethtool -K p4eth1 tx off 2>/dev/null || true')
      end

      # ── Default routes and static ARP on hosts ─────────────────────────
      conns.each do |conn|
        host_cname = "#{prefix}_#{conn['host_name']}"
        gw_ip      = conn['sw_ip'].split('/').first

        # Default gateway = switch port IP on this link
        capture3!('docker', 'exec', host_cname, 'route', 'add', 'default', 'gw', gw_ip)

        # Static ARP: all other hosts + all switch port IPs
        conns.each do |other|
          capture3!('docker', 'exec', host_cname, 'sh', '-c',
            "arp -i p4eth1 -s #{other['host_ip'].split('/').first} #{other['host_mac']}")
          capture3!('docker', 'exec', host_cname, 'sh', '-c',
            "arp -i p4eth1 -s #{other['sw_ip'].split('/').first} #{other['sw_mac']}")
        end
      end

      # ── Static ARP on switch ───────────────────────────────────────────
      conns.each do |conn|
        sw_iface = "eth#{conn['port']}"
        host_ip  = conn['host_ip'].split('/').first
        capture3!('docker', 'exec', sw_cname, 'sh', '-c',
          "arp -i #{sw_iface} -s #{host_ip} #{conn['host_mac']}")
      end

      # ── Start BMv2 ────────────────────────────────────────────────────
      port_flags = conns.map { |c| "-i #{c['port']}@eth#{c['port']}" }.join(' ')
      bmv2_cmd   = "nohup simple_switch --thrift-port #{thrift_port} " \
                   "#{port_flags} /workspace/#{json_name} " \
                   "--log-console >> /workspace/switch.log 2>&1 &"
      capture3!('docker', 'exec', sw_cname, 'sh', '-c', bmv2_cmd)

      sleep 3  # wait for thrift port to open

      # ── Load forwarding rules ──────────────────────────────────────────
      rules = topo['forwarding_rules'] || []
      if rules.any?
        rules_input = rules.join("\n") + "\n"
        stdout, stderr, = Timeout.timeout(15) do
          Open3.capture3('docker', 'exec', '-i', sw_cname,
                         'simple_switch_CLI', '--thrift-port', thrift_port.to_s,
                         stdin_data: rules_input)
        end
        result[:rules_log] = (stdout.to_s + stderr.to_s).strip
      end

      sleep 1

      # ── Start tcpdump on every host (best-effort, -c 200 auto-stops) ──
      seen_td = Set.new
      conns.each do |conn|
        next unless seen_td.add?(conn['host_name'])
        system('docker', 'exec', "#{prefix}_#{conn['host_name']}", 'sh', '-c',
               'tcpdump -i p4eth1 -n -e -tt -l -c 200 > /tmp/cap.txt 2>/dev/null &')
      end

      # ── Run traffic test ───────────────────────────────────────────────
      traffic = topo['traffic_test']
      if traffic && traffic['from'].present? && traffic['command'].present?
        sender = "#{prefix}_#{traffic['from']}"
        stdout, stderr, = Timeout.timeout(TRAFFIC_TIMEOUT) do
          Open3.capture3('docker', 'exec', sender, 'sh', '-c', traffic['command'])
        end
        result[:traffic_log] = (stdout.to_s + stderr.to_s).strip
      end

      # ── Collect packet captures ────────────────────────────────────────
      sleep 0.5  # let tcpdump flush final packets
      captures = {}
      conns.map { |c| c['host_name'] }.uniq.each do |host_name|
        out, = Open3.capture3('docker', 'exec', "#{prefix}_#{host_name}",
                              'sh', '-c', 'cat /tmp/cap.txt 2>/dev/null')
        captures[host_name] = out.strip if out.strip.present?
      end
      result[:packet_captures] = captures unless captures.empty?

      # ── Collect switch log ─────────────────────────────────────────────
      switch_log_path = File.join(out_dir, 'switch.log')
      if File.exist?(switch_log_path)
        result[:switch_log] = File.readlines(switch_log_path).last(150).join.strip
      end

    rescue => e
      result[:error] = "Topology error: #{e.message}"
    ensure
      containers.reverse_each do |c|
        system('docker', 'stop', '-t', '2', c, out: File::NULL, err: File::NULL) rescue nil
      end
    end

    result
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  def container_pid(name)
    stdout, = Open3.capture3('docker', 'inspect', '--format', '{{.State.Pid}}', name)
    stdout.strip
  end

  def netns_exec(pid, *args)
    capture3!('nsenter', '-t', pid.to_s, '-n', '--', *args)
  end

  def capture3!(*args)
    stdout, stderr, status = Open3.capture3(*args)
    raise "#{args.first} failed: #{stderr.strip}" unless status.success?
    stdout
  end

  # ── Feedback builders ──────────────────────────────────────────────────────

  def build_topology_feedback(compile_log, result)
    parts = [section('Compilation (p4lang/p4c · bmv2 · v1model)', compile_log)]
    parts << section('Error',             result[:error])      if result[:error].present?
    parts << section('Forwarding rules',  result[:rules_log])  if result[:rules_log].present?
    parts << section('Traffic test',      result[:traffic_log]) if result[:traffic_log].present?
    parts << section('BMv2 switch log',   result[:switch_log]) if result[:switch_log].present?
    parts.join("\n\n")
  end

  def build_feedback(compile_log, switch_log)
    parts = [section('Compilation successful (p4lang/p4c · bmv2 · v1model)', compile_log)]
    parts << section('BMv2 simple_switch log', switch_log) if switch_log.present?
    parts.join("\n\n")
  end

  def section(title, body)
    return "── #{title} ──" if body.blank?
    "── #{title} ──\n\n#{body}"
  end
end
