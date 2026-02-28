# frozen_string_literal: true

require_relative "rule_evaluator"
require_relative "instruction_builder"
require_relative "logger"
require_relative "../providers/base"

module Baton
  module Engine
    # Main orchestration loop.
    #
    # Executes movements in sequence, calling the appropriate provider
    # for each step, evaluating rules, and transitioning until the
    # workflow completes (no matching rule or explicit COMPLETE).
    class PieceEngine
      COMPLETE = "__COMPLETE__"
      MAX_ITERATIONS = 50

      attr_reader :state

      def initialize(config, task: nil, plan: nil, working_dir: nil, logger: nil)
        @config = config
        @task = task || config.task || ""
        @plan = plan || ""
        @working_dir = working_dir
        @logger = logger || Logger.new
        @state = Models::PieceState.new(
          current_movement: config.start
        )
        @pending_feedback = nil
      end

      def run
        iteration = 0

        loop do
          iteration += 1
          if iteration > MAX_ITERATIONS
            @logger.error("Max iterations (#{MAX_ITERATIONS}) exceeded — aborting")
            break
          end

          movement = current_movement
          unless movement
            @logger.error("Movement '#{@state.current_movement}' not found")
            break
          end

          @logger.movement_start(movement.name)
          response = execute_movement(movement)
          @state.previous_response = response.result
          @state.history << movement.name

          # Store session_id for potential resume
          if response.session_id
            @state.session_ids[movement.provider] = response.session_id
          end

          # Interactive mode: show result and ask for human input
          if movement.interactive
            next_name = handle_interactive(movement, response)
            break if next_name.nil?

            if next_name == :feedback
              # Re-run the same movement with feedback
              next
            end

            if next_name.upcase == COMPLETE
              @logger.movement_end(movement.name, nil)
              break
            end

            @logger.movement_end(movement.name, next_name)
            @state.current_movement = next_name
            next
          end

          # Non-interactive: evaluate rules to determine next movement
          matched_rule = RuleEvaluator.evaluate(response.result, movement.rules)

          if matched_rule
            @logger.rule_matched(matched_rule)
            next_name = matched_rule.next_movement

            if next_name.upcase == COMPLETE
              @logger.movement_end(movement.name, nil)
              break
            end

            @logger.movement_end(movement.name, next_name)
            @state.current_movement = next_name
          else
            @logger.rule_no_match
            @logger.movement_end(movement.name, nil)
            break
          end
        end

        @logger.complete(@state.history)
        @state
      end

      private

      def current_movement
        @config.movements[@state.current_movement]
      end

      def handle_interactive(movement, response)
        @logger.show_interactive_result(response.result)
        human_input = @logger.prompt_human

        if human_input.empty?
          @logger.human_approved
          # Take the first rule's next movement
          first_rule = movement.rules.first
          return first_rule&.next_movement
        end

        # Human provided feedback — re-run the movement
        @logger.human_feedback
        @pending_feedback = human_input
        :feedback
      end

      def execute_movement(movement)
        provider = Providers::Registry.fetch(movement.provider)

        if @pending_feedback
          # Interactive re-run: send only the feedback (session is resumed)
          prompt = @pending_feedback
          @pending_feedback = nil
        else
          # Normal execution: build from template
          prompt = InstructionBuilder.build(
            movement.prompt,
            task: @task,
            previous_response: @state.previous_response,
            plan: @plan
          )

          # Inject rule choices only for non-interactive movements
          prompt = RuleEvaluator.inject_rules(prompt, movement.rules) unless movement.interactive
        end

        # Load persona
        system_prompt = load_persona(movement.persona)

        @logger.provider_call(provider.name, prompt)

        provider.call(prompt, {
          system_prompt: system_prompt,
          tools: movement.tools,
          sandbox: movement.sandbox,
          max_turns: movement.max_turns,
          session_id: @state.session_ids[movement.provider],
          working_dir: @working_dir
        })
      end

      def load_persona(persona_path)
        return "" if persona_path.nil? || persona_path.empty?

        full_path = File.expand_path(persona_path, Baton.root)
        return "" unless File.exist?(full_path)

        File.read(full_path)
      end
    end
  end
end
