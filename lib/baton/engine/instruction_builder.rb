# frozen_string_literal: true

module Baton
  module Engine
    # Expands template variables in movement prompts.
    #
    # Supported placeholders:
    #   {task}              – the task description
    #   {previous_response} – output from the previous movement
    module InstructionBuilder
      module_function

      def build(template, task:, previous_response: "")
        result = template.dup
        result.gsub!("{task}", task.to_s)
        result.gsub!("{previous_response}", previous_response.to_s)
        result
      end
    end
  end
end
