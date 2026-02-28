# frozen_string_literal: true

require "spec_helper"

# MockProvider that returns scripted responses for testing.
class MockProvider < Baton::Providers::Base
  attr_reader :calls

  def initialize(name, responses: [])
    super(name)
    @responses = responses
    @call_index = 0
    @calls = []
  end

  def call(prompt, options = {})
    @calls << { prompt: prompt, options: options }
    response = @responses[@call_index] || Baton::Models::AgentResponse.new(
      result: "default response",
      session_id: nil,
      cost_usd: nil,
      raw: "default response"
    )
    @call_index += 1
    response
  end
end

RSpec.describe "Baton" do
  describe Baton::Models::PieceLoader do
    let(:yaml_content) do
      {
        "name" => "test-piece",
        "task" => "build a widget",
        "start" => "plan",
        "movements" => [
          {
            "name" => "plan",
            "provider" => "claude",
            "persona" => "",
            "prompt" => "Plan: {task}",
            "tools" => "Read,Glob",
            "max_turns" => 10,
            "rules" => [
              { "condition" => "approved", "next" => "implement" }
            ]
          },
          {
            "name" => "implement",
            "provider" => "claude",
            "persona" => "",
            "prompt" => "Implement: {previous_response}",
            "tools" => "Read,Write",
            "max_turns" => 20,
            "rules" => []
          }
        ]
      }
    end

    it "parses raw YAML hash into PieceConfig" do
      config = Baton::Models::PieceLoader.parse(yaml_content)

      expect(config.name).to eq("test-piece")
      expect(config.task).to eq("build a widget")
      expect(config.start).to eq("plan")
      expect(config.movements.keys).to eq(%w[plan implement])
    end

    it "builds rules with correct tag and index" do
      config = Baton::Models::PieceLoader.parse(yaml_content)
      rules = config.movements["plan"].rules

      expect(rules.size).to eq(1)
      expect(rules[0].tag).to eq("PLAN")
      expect(rules[0].index).to eq(0)
      expect(rules[0].condition).to eq("approved")
      expect(rules[0].next_movement).to eq("implement")
    end

    it "defaults start to first movement" do
      yaml_content.delete("start")
      config = Baton::Models::PieceLoader.parse(yaml_content)
      expect(config.start).to eq("plan")
    end

    it "loads from a YAML file" do
      path = File.expand_path("../config/pieces/default.yaml", __dir__)
      config = Baton::Models::PieceLoader.load_file(path)

      expect(config.name).to eq("default")
      expect(config.movements).to include("plan", "implement", "review", "fix")
    end
  end

  describe Baton::Engine::RuleEvaluator do
    let(:rules) do
      [
        Baton::Models::Rule.new(tag: "REVIEW", index: 0, condition: "approved", next_movement: "__COMPLETE__"),
        Baton::Models::Rule.new(tag: "REVIEW", index: 1, condition: "needs_fix", next_movement: "fix")
      ]
    end

    it "matches exact tag [REVIEW:0]" do
      result = Baton::Engine::RuleEvaluator.evaluate("The code looks good. [REVIEW:0]", rules)
      expect(result).to eq(rules[0])
      expect(result.next_movement).to eq("__COMPLETE__")
    end

    it "matches exact tag [REVIEW:1]" do
      result = Baton::Engine::RuleEvaluator.evaluate("Found issues. [REVIEW:1]", rules)
      expect(result).to eq(rules[1])
      expect(result.next_movement).to eq("fix")
    end

    it "matches case-insensitively" do
      result = Baton::Engine::RuleEvaluator.evaluate("[review:0] all good", rules)
      expect(result).to eq(rules[0])
    end

    it "falls back to fuzzy condition match" do
      result = Baton::Engine::RuleEvaluator.evaluate("The code is approved and ready to merge", rules)
      expect(result).to eq(rules[0])
    end

    it "matches needs_fix via fuzzy" do
      result = Baton::Engine::RuleEvaluator.evaluate("This implementation needs_fix before merging", rules)
      expect(result).to eq(rules[1])
    end

    it "returns nil when no match" do
      result = Baton::Engine::RuleEvaluator.evaluate("unrelated text", rules)
      expect(result).to be_nil
    end

    it "returns nil for empty rules" do
      result = Baton::Engine::RuleEvaluator.evaluate("anything", [])
      expect(result).to be_nil
    end

    it "injects rule choices into prompt" do
      prompt = Baton::Engine::RuleEvaluator.inject_rules("Do the review", rules)
      expect(prompt).to include("[REVIEW:0]")
      expect(prompt).to include("[REVIEW:1]")
      expect(prompt).to include("approved")
      expect(prompt).to include("needs_fix")
    end

    it "returns prompt unchanged when no rules" do
      prompt = Baton::Engine::RuleEvaluator.inject_rules("Do the review", [])
      expect(prompt).to eq("Do the review")
    end

    it "matches generic [MOVEMENT:N] pattern" do
      result = Baton::Engine::RuleEvaluator.evaluate("I choose [MOVEMENT:1]", rules)
      expect(result).to eq(rules[1])
    end
  end

  describe Baton::Engine::InstructionBuilder do
    it "replaces {task} placeholder" do
      result = Baton::Engine::InstructionBuilder.build("Do: {task}", task: "build a widget")
      expect(result).to eq("Do: build a widget")
    end

    it "replaces {previous_response} placeholder" do
      result = Baton::Engine::InstructionBuilder.build(
        "Review: {previous_response}",
        task: "",
        previous_response: "the plan output"
      )
      expect(result).to eq("Review: the plan output")
    end

    it "replaces both placeholders" do
      result = Baton::Engine::InstructionBuilder.build(
        "Task: {task}\nPrev: {previous_response}",
        task: "test task",
        previous_response: "prev output"
      )
      expect(result).to eq("Task: test task\nPrev: prev output")
    end

    it "handles missing previous_response gracefully" do
      result = Baton::Engine::InstructionBuilder.build("Do: {task} ({previous_response})", task: "hi")
      expect(result).to eq("Do: hi ()")
    end

    it "replaces {plan} placeholder" do
      result = Baton::Engine::InstructionBuilder.build(
        "Implement:\n{plan}\nTask: {task}",
        task: "add auth",
        plan: "## Step 1\nCreate user model"
      )
      expect(result).to eq("Implement:\n## Step 1\nCreate user model\nTask: add auth")
    end

    it "handles missing plan gracefully" do
      result = Baton::Engine::InstructionBuilder.build("Plan: {plan}", task: "x")
      expect(result).to eq("Plan: ")
    end
  end

  describe Baton::Providers::Registry do
    it "registers and fetches providers" do
      provider = MockProvider.new("test")
      Baton::Providers::Registry.register("test", provider)

      expect(Baton::Providers::Registry.fetch("test")).to eq(provider)
    end

    it "raises for unknown provider" do
      expect { Baton::Providers::Registry.fetch("nonexistent") }
        .to raise_error(ArgumentError, /Unknown provider/)
    end

    it "lists registered keys" do
      Baton::Providers::Registry.register("a", MockProvider.new("a"))
      Baton::Providers::Registry.register("b", MockProvider.new("b"))

      expect(Baton::Providers::Registry.keys).to contain_exactly("a", "b")
    end

    it "clears all providers" do
      Baton::Providers::Registry.register("x", MockProvider.new("x"))
      Baton::Providers::Registry.clear!
      expect(Baton::Providers::Registry.keys).to be_empty
    end
  end

  describe Baton::Models::PieceState do
    it "initializes with defaults" do
      state = Baton::Models::PieceState.new(current_movement: "plan")
      expect(state.session_ids).to eq({})
      expect(state.previous_response).to eq("")
      expect(state.history).to eq([])
    end
  end

  describe Baton::Engine::PieceEngine, "integration with MockProvider" do
    let(:logger) { Baton::Engine::Logger.new(output: StringIO.new) }

    context "simple two-step workflow: plan → implement" do
      let(:config) do
        Baton::Models::PieceLoader.parse(
          "name" => "two-step",
          "task" => "build feature",
          "start" => "plan",
          "movements" => [
            {
              "name" => "plan",
              "provider" => "mock",
              "persona" => "",
              "prompt" => "Plan: {task}",
              "tools" => "Read",
              "max_turns" => 5,
              "rules" => [
                { "condition" => "approved", "next" => "implement" }
              ]
            },
            {
              "name" => "implement",
              "provider" => "mock",
              "persona" => "",
              "prompt" => "Implement: {previous_response}",
              "tools" => "Read,Write",
              "max_turns" => 10,
              "rules" => []
            }
          ]
        )
      end

      it "executes plan then implement and completes" do
        mock = MockProvider.new("mock", responses: [
          Baton::Models::AgentResponse.new(
            result: "Here is the plan. [PLAN:0]",
            session_id: "sess-1",
            cost_usd: 0.01,
            raw: "raw1"
          ),
          Baton::Models::AgentResponse.new(
            result: "Implementation done.",
            session_id: "sess-2",
            cost_usd: 0.05,
            raw: "raw2"
          )
        ])
        Baton::Providers::Registry.register("mock", mock)

        engine = Baton::Engine::PieceEngine.new(config, task: "build feature", logger: logger)
        state = engine.run

        expect(state.history).to eq(%w[plan implement])
        expect(mock.calls.size).to eq(2)

        # Check that the plan prompt included {task} expansion
        expect(mock.calls[0][:prompt]).to include("build feature")
        # Check that implement prompt included previous response
        expect(mock.calls[1][:prompt]).to include("Here is the plan")
      end
    end

    context "full review loop: plan → implement → review → fix → review → complete" do
      let(:config) do
        Baton::Models::PieceLoader.parse(
          "name" => "full-loop",
          "task" => "add login",
          "start" => "plan",
          "movements" => [
            {
              "name" => "plan",
              "provider" => "mock_claude",
              "persona" => "",
              "prompt" => "Plan: {task}",
              "tools" => "Read",
              "max_turns" => 5,
              "rules" => [
                { "condition" => "approved", "next" => "implement" }
              ]
            },
            {
              "name" => "implement",
              "provider" => "mock_claude",
              "persona" => "",
              "prompt" => "Implement based on: {previous_response}",
              "tools" => "Read,Write",
              "max_turns" => 10,
              "rules" => [
                { "condition" => "implementation complete", "next" => "review" }
              ]
            },
            {
              "name" => "review",
              "provider" => "mock_codex",
              "persona" => "",
              "prompt" => "Review: {previous_response}",
              "tools" => "",
              "sandbox" => "read-only",
              "max_turns" => 5,
              "rules" => [
                { "condition" => "approved", "next" => "__COMPLETE__" },
                { "condition" => "needs_fix", "next" => "fix" }
              ]
            },
            {
              "name" => "fix",
              "provider" => "mock_claude",
              "persona" => "",
              "prompt" => "Fix: {previous_response}",
              "tools" => "Read,Write",
              "max_turns" => 10,
              "rules" => [
                { "condition" => "fix complete", "next" => "review" }
              ]
            }
          ]
        )
      end

      it "loops through fix cycle and completes" do
        mock_claude = MockProvider.new("mock_claude", responses: [
          # plan response
          Baton::Models::AgentResponse.new(result: "Plan ready. [PLAN:0]", session_id: "c1", cost_usd: 0.01, raw: ""),
          # implement response
          Baton::Models::AgentResponse.new(result: "Code done. [IMPLEMENT:0]", session_id: "c2", cost_usd: 0.05, raw: ""),
          # fix response
          Baton::Models::AgentResponse.new(result: "Fixed the bugs. [FIX:0]", session_id: "c3", cost_usd: 0.03, raw: "")
        ])

        mock_codex = MockProvider.new("mock_codex", responses: [
          # first review: needs fix
          Baton::Models::AgentResponse.new(result: "Found bugs. [REVIEW:1]", session_id: "x1", cost_usd: nil, raw: ""),
          # second review: approved
          Baton::Models::AgentResponse.new(result: "All good. [REVIEW:0]", session_id: "x2", cost_usd: nil, raw: "")
        ])

        Baton::Providers::Registry.register("mock_claude", mock_claude)
        Baton::Providers::Registry.register("mock_codex", mock_codex)

        engine = Baton::Engine::PieceEngine.new(config, task: "add login", logger: logger)
        state = engine.run

        expect(state.history).to eq(%w[plan implement review fix review])
        expect(mock_claude.calls.size).to eq(3)
        expect(mock_codex.calls.size).to eq(2)
      end
    end

    context "workflow completes immediately when no rules match" do
      let(:config) do
        Baton::Models::PieceLoader.parse(
          "name" => "single",
          "task" => "just do it",
          "start" => "run",
          "movements" => [
            {
              "name" => "run",
              "provider" => "mock",
              "persona" => "",
              "prompt" => "{task}",
              "rules" => [
                { "condition" => "very_specific_condition", "next" => "other" }
              ]
            }
          ]
        )
      end

      it "stops when no rules match" do
        mock = MockProvider.new("mock", responses: [
          Baton::Models::AgentResponse.new(result: "done", session_id: nil, cost_usd: nil, raw: "")
        ])
        Baton::Providers::Registry.register("mock", mock)

        engine = Baton::Engine::PieceEngine.new(config, task: "just do it", logger: logger)
        state = engine.run

        expect(state.history).to eq(%w[run])
      end
    end

    context "plan file workflow: implement → review with {plan} expansion" do
      let(:config) do
        Baton::Models::PieceLoader.parse(
          "name" => "from-plan",
          "task" => "add auth",
          "start" => "implement",
          "movements" => [
            {
              "name" => "implement",
              "provider" => "mock",
              "persona" => "",
              "prompt" => "Implement:\n{plan}\nTask: {task}",
              "tools" => "Read,Write",
              "max_turns" => 10,
              "rules" => [
                { "condition" => "implementation complete", "next" => "review" }
              ]
            },
            {
              "name" => "review",
              "provider" => "mock",
              "persona" => "",
              "prompt" => "Review:\n{previous_response}\nPlan:\n{plan}",
              "sandbox" => "read-only",
              "max_turns" => 5,
              "rules" => [
                { "condition" => "approved", "next" => "__COMPLETE__" }
              ]
            }
          ]
        )
      end

      it "injects plan content into prompts and skips plan step" do
        mock = MockProvider.new("mock", responses: [
          Baton::Models::AgentResponse.new(
            result: "Implemented login. [IMPLEMENT:0]",
            session_id: nil, cost_usd: nil, raw: ""
          ),
          Baton::Models::AgentResponse.new(
            result: "Looks good. [REVIEW:0]",
            session_id: nil, cost_usd: nil, raw: ""
          )
        ])
        Baton::Providers::Registry.register("mock", mock)

        plan_text = "## Plan\n1. Create User model\n2. Add login endpoint"
        engine = Baton::Engine::PieceEngine.new(config, task: "add auth", plan: plan_text, logger: logger)
        state = engine.run

        # Skipped plan, started at implement
        expect(state.history).to eq(%w[implement review])

        # Plan content was injected into implement prompt
        expect(mock.calls[0][:prompt]).to include("Create User model")
        expect(mock.calls[0][:prompt]).to include("add auth")

        # Plan content was injected into review prompt too
        expect(mock.calls[1][:prompt]).to include("Create User model")
      end

      it "loads from-plan.yaml piece file" do
        path = File.expand_path("../config/pieces/from-plan.yaml", __dir__)
        config = Baton::Models::PieceLoader.load_file(path)

        expect(config.name).to eq("from-plan")
        expect(config.start).to eq("implement")
        expect(config.movements.keys).to eq(%w[implement review fix])
      end
    end

    context "max iteration guard" do
      let(:config) do
        Baton::Models::PieceLoader.parse(
          "name" => "infinite",
          "task" => "loop forever",
          "start" => "loop",
          "movements" => [
            {
              "name" => "loop",
              "provider" => "mock",
              "persona" => "",
              "prompt" => "{task}",
              "rules" => [
                { "condition" => "again", "next" => "loop" }
              ]
            }
          ]
        )
      end

      it "breaks after MAX_ITERATIONS" do
        responses = Array.new(60) do
          Baton::Models::AgentResponse.new(result: "do it again [LOOP:0]", session_id: nil, cost_usd: nil, raw: "")
        end
        mock = MockProvider.new("mock", responses: responses)
        Baton::Providers::Registry.register("mock", mock)

        engine = Baton::Engine::PieceEngine.new(config, task: "loop forever", logger: logger)
        state = engine.run

        expect(state.history.size).to eq(Baton::Engine::PieceEngine::MAX_ITERATIONS)
      end
    end
  end

  describe Baton::Engine::Logger do
    it "outputs movement lifecycle messages" do
      output = StringIO.new
      log = Baton::Engine::Logger.new(output: output)

      log.movement_start("plan")
      log.provider_call("claude", "do something")
      log.rule_matched(Baton::Models::Rule.new(tag: "PLAN", index: 0, condition: "ok", next_movement: "impl"))
      log.movement_end("plan", "impl")
      log.complete(%w[plan impl])

      text = output.string
      expect(text).to include("plan")
      expect(text).to include("impl")
      expect(text).to include("claude")
    end
  end
end
