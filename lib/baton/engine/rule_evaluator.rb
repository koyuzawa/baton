# frozen_string_literal: true

module Baton
  module Engine
    # Evaluates agent output against movement rules to determine
    # the next movement transition.
    #
    # 1. Exact tag match: looks for [MOVEMENT:N] in the output
    # 2. Fuzzy fallback: checks if the condition text appears in the output
    module RuleEvaluator
      module_function

      # Appends rule choice instructions to the prompt.
      # e.g. "[PLAN:0] — approved\n[PLAN:1] — needs revision"
      def inject_rules(prompt, rules)
        return prompt if rules.nil? || rules.empty?

        choices = rules.map do |rule|
          "[#{rule.tag}:#{rule.index}] — #{rule.condition}"
        end

        "#{prompt}\n\n---\nRespond with ONE of the following tags to indicate your decision:\n#{choices.join("\n")}"
      end

      # Evaluates the agent output and returns the matching Rule, or nil.
      def evaluate(output, rules)
        return nil if rules.nil? || rules.empty?

        # 1. Exact tag match: [TAG:N]
        rules.each do |rule|
          pattern = /\[#{Regexp.escape(rule.tag)}:#{rule.index}\]/i
          return rule if output.match?(pattern)
        end

        # 2. Generic [MOVEMENT:N] pattern
        if (match = output.match(/\[MOVEMENT:(\d+)\]/i))
          idx = match[1].to_i
          return rules[idx] if idx < rules.size
        end

        # 3. Fuzzy fallback: condition text appears in output
        rules.each do |rule|
          return rule if output.downcase.include?(rule.condition.downcase)
        end

        nil
      end
    end
  end
end
