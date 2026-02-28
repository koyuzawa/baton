# frozen_string_literal: true

module Baton
  module Models
    # A single rule attached to a movement.
    # tag   – label injected into the prompt, e.g. "PLAN"
    # index – numeric index of this rule within the movement
    # condition – human-readable condition text
    # next_movement – name of the movement to jump to when matched
    Rule = Struct.new(:tag, :index, :condition, :next_movement, keyword_init: true)

    # One step in the piece workflow.
    # name        – unique identifier (e.g. "plan", "implement")
    # provider    – provider key (e.g. "claude", "codex")
    # persona     – path to the persona markdown file
    # prompt      – the prompt template (may contain {task}, {previous_response})
    # tools       – allowed tool list (provider-specific)
    # sandbox     – sandbox mode for codex ("read-only", "workspace-write")
    # max_turns   – maximum conversation turns
    # rules       – array of Rule
    # interactive – if true, pause for human input after each execution
    Movement = Struct.new(:name, :provider, :persona, :prompt, :tools, :sandbox, :max_turns, :rules, :interactive, keyword_init: true)

    # Top-level configuration loaded from a piece YAML file.
    # name       – piece name
    # task       – default task description
    # movements  – ordered Hash (name → Movement)
    # start      – name of the first movement
    PieceConfig = Struct.new(:name, :task, :movements, :start, keyword_init: true)

    # Runtime state of a piece execution.
    # current_movement – name of the active movement
    # session_ids      – Hash (provider_key → session_id) for resume
    # previous_response – last agent response text
    # history          – array of completed movement names
    PieceState = Struct.new(:current_movement, :session_ids, :previous_response, :history, keyword_init: true) do
      def initialize(**)
        super
        self.session_ids      ||= {}
        self.previous_response ||= ""
        self.history           ||= []
      end
    end

    # Unified response returned by every provider.
    # result     – the text output from the agent
    # session_id – session identifier for resuming
    # cost_usd   – total cost in USD (Float or nil)
    # raw        – raw response data (Hash or String)
    AgentResponse = Struct.new(:result, :session_id, :cost_usd, :raw, keyword_init: true)
  end
end
