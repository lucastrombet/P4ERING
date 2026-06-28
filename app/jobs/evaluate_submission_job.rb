require 'open3'
require 'timeout'

class EvaluateSubmissionJob < ApplicationJob
  queue_as :default

  P4C_IMAGE = 'p4lang/p4c'
  COMPILE_TIMEOUT = 30

  def perform(submission_id)
    submission = Submission.find_by(id: submission_id)
    return unless submission

    submission.update!(status: 'evaluating')

    if submission.exercise.language == 'P4'
      compile_p4(submission)
    else
      submission.update!(
        status: 'failed',
        feedback: "Sandbox only supports P4 exercises. Got: #{submission.exercise.language}"
      )
    end
  rescue => e
    submission&.update(status: 'failed', feedback: "Sandbox error: #{e.message}")
  end

  private

  def compile_p4(submission)
    Dir.mktmpdir("p4_#{submission.id}_") do |dir|
      File.write(File.join(dir, 'program.p4'), submission.code)

      stdout, stderr, status = Timeout.timeout(COMPILE_TIMEOUT) do
        Open3.capture3(
          'docker', 'run', '--rm',
          '--network=none',
          '--memory=128m',
          '--cpus=0.5',
          '--read-only',
          '--tmpfs', '/tmp:size=32m',
          '-v', "#{dir}:/workspace:ro",
          P4C_IMAGE,
          'p4c', '--target', 'bmv2', '--arch', 'v1model',
          '-o', '/tmp/out', '/workspace/program.p4'
        )
      end

      compiler_output = stderr.presence || stdout
      if status.success?
        submission.update!(
          status: 'completed',
          feedback: format_feedback('Compilation successful (p4lang/p4c · bmv2 · v1model)', compiler_output)
        )
      else
        submission.update!(
          status: 'failed',
          feedback: format_feedback('Compilation failed', compiler_output)
        )
      end
    end
  rescue Timeout::Error
    submission.update(status: 'failed', feedback: "Compilation timed out after #{COMPILE_TIMEOUT} seconds.")
  end

  def format_feedback(header, compiler_output)
    return header if compiler_output.blank?
    "#{header}\n\n#{compiler_output.strip}"
  end
end
