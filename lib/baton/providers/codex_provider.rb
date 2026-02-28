# frozen_string_literal: true

require "open3"
require_relative "base"

module Baton
  module Providers
    # Calls OpenAI Codex CLI as a subprocess.
    #
    # codex exec --sandbox read-only "system_prompt\n\nprompt"
    #
    # System prompt is concatenated into the prompt because
    # codex exec does not support a separate --system-prompt flag.
    class CodexProvider < Base
      def initialize
        super("codex")
      end

      def call(prompt, options = {})
        full_prompt = build_prompt(prompt, options)
        cmd = build_command(full_prompt, options)
        stdout, stderr, status = Open3.capture3(*cmd)

        unless status.success?
          raise "Codex CLI failed (exit #{status.exitstatus}): #{stderr}"
        end

        Models::AgentResponse.new(
          result: stdout.strip,
          session_id: extract_session_id(stdout),
          cost_usd: nil,
          raw: stdout
        )
      end

      private

      def build_prompt(prompt, options)
        if options[:system_prompt] && !options[:system_prompt].empty?
          "#{options[:system_prompt]}\n\n#{prompt}"
        else
          prompt
        end
      end

      def build_command(full_prompt, options)
        sandbox = options[:sandbox] || "read-only"

        if options[:session_id]
          ["codex", "exec", "resume", options[:session_id]]
        else
          ["codex", "exec", "--sandbox", sandbox, full_prompt]
        end
      end

      def extract_session_id(stdout)
        match = stdout.match(/session[_-]id[:\s]+(\S+)/i)
        match&.captures&.first
      end
    end
  end
end
