# Parses one `iperf3 -J` client report (the raw stdout of a traffic test)
# into the flat metrics hash used by SubmissionEvaluator's traffic_metric
# checks and by the feedback's human-readable summary. Returns nil for
# anything that isn't an iperf3 JSON report (legacy ping tests, timeouts,
# error output) — callers treat nil as "no metrics for this flow".
module IperfReport
  module_function

  def parse(output)
    json = JSON.parse(output.to_s)
    return nil unless json.is_a?(Hash) && json['end'].is_a?(Hash)

    if json['end']['sum'] && json['end']['sum']['jitter_ms']
      udp_metrics(json)
    elsif json['end']['sum_received']
      tcp_metrics(json)
    end
  rescue JSON::ParserError
    nil
  end

  def summary(metrics)
    parts = ["#{metrics['throughput_mbps']} Mbits/sec"]
    parts << "#{metrics['retransmits']} retransmissions" if metrics['retransmits']
    parts << "jitter #{metrics['jitter_ms']} ms"         if metrics['jitter_ms']
    parts << "loss #{metrics['loss_percent']}%"          if metrics['loss_percent']
    parts.join(', ')
  end

  def tcp_metrics(json)
    {
      'protocol'        => 'TCP',
      'throughput_mbps' => mbps(json.dig('end', 'sum_received', 'bits_per_second')),
      'retransmits'     => json.dig('end', 'sum_sent', 'retransmits'),
    }.compact
  end

  def udp_metrics(json)
    sum = json['end']['sum']
    {
      'protocol'        => 'UDP',
      'throughput_mbps' => mbps(sum['bits_per_second']),
      'jitter_ms'       => sum['jitter_ms']&.round(3),
      'loss_percent'    => sum['lost_percent']&.round(2),
    }.compact
  end

  def mbps(bits_per_second)
    return nil unless bits_per_second
    (bits_per_second / 1_000_000.0).round(2)
  end
end
