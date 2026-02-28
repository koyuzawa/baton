# frozen_string_literal: true

require "pastel"

module Baton
  module Engine
    # Coloured terminal logger using Pastel.
    class Logger
      def initialize(output: $stdout)
        @output = output
        @pastel = Pastel.new(enabled: output.respond_to?(:tty?) ? output.tty? : false)
      end

      def movement_start(name)
        @output.puts @pastel.cyan.bold("▶ Movement: #{name}")
      end

      def movement_end(name, next_name)
        @output.puts @pastel.green("✓ #{name} → #{next_name || 'COMPLETE'}")
        @output.puts
      end

      def provider_call(provider_name, prompt_preview)
        truncated = prompt_preview.to_s[0, 120]
        @output.puts @pastel.yellow("  ⚡ #{provider_name}: #{truncated}...")
      end

      def rule_matched(rule)
        @output.puts @pastel.magenta("  ✦ Rule matched: [#{rule.tag}:#{rule.index}] → #{rule.next_movement}")
      end

      def rule_no_match
        @output.puts @pastel.red("  ✗ No rule matched — workflow complete")
      end

      def error(message)
        @output.puts @pastel.red.bold("ERROR: #{message}")
      end

      def info(message)
        @output.puts @pastel.white("  #{message}")
      end

      def complete(history)
        @output.puts @pastel.green.bold("✓ Piece complete! Movements: #{history.join(' → ')}")
      end
    end
  end
end
