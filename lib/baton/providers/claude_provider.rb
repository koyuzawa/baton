# frozen_string_literal: true

require "json"
require "open3"
require_relative "base"

module Baton
  module Providers
    # Calls Claude Code CLI as a subprocess.
    #
    # claude -p \
    #   --system-prompt "..." \
    #   --allowedTools "Read,Glob,Grep" \
    #   --output-format json \
    #   --max-turns 20 \
    #   --dangerously-skip-permissions \
    #   "prompt"
    class ClaudeProvider < Base
      def initialize
        super("claude")
      end

      def call(prompt, options = {})
        cmd = build_command(prompt, options)
        stdout, stderr, status = Open3.capture3(*cmd)

        unless status.success?
          raise "Claude CLI failed (exit #{status.exitstatus}): #{stderr}"
        end

        parse_response(stdout)
      end

      private

      def build_command(prompt, options)
        cmd = ["claude", "-p"]

        if options[:system_prompt] && !options[:system_prompt].empty?
          cmd += ["--system-prompt", options[:system_prompt]]
        end

        if options[:tools] && !options[:tools].empty?
          cmd += ["--allowedTools", options[:tools]]
        end

        cmd += ["--output-format", "json"]
        cmd += ["--max-turns", (options[:max_turns] || 20).to_s]
        cmd << "--dangerously-skip-permissions"

        if options[:session_id]
          cmd += ["--resume", options[:session_id]]
        end

        cmd << prompt
        cmd
      end

      def parse_response(stdout)
        data = JSON.parse(stdout)
        result_text = extract_result(data)

        Models::AgentResponse.new(
          result: result_text,
          session_id: data["session_id"],
          cost_usd: data["total_cost_usd"]&.to_f,
          raw: data
        )
      rescue JSON::ParserError
        Models::AgentResponse.new(
          result: stdout.strip,
          session_id: nil,
          cost_usd: nil,
          raw: stdout
        )
      end

      def extract_result(data)
        return data["result"] if data["result"].is_a?(String)

        if data["result"].is_a?(Array)
          data["result"]
            .select { |block| block["type"] == "text" }
            .map { |block| block["text"] }
            .join("\n")
        else
          data.to_s
        end
      end
    end
  end
end
