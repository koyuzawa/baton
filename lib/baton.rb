# frozen_string_literal: true

require_relative "baton/models/types"
require_relative "baton/models/piece_loader"
require_relative "baton/providers/base"
require_relative "baton/providers/claude_provider"
require_relative "baton/providers/codex_provider"
require_relative "baton/engine/rule_evaluator"
require_relative "baton/engine/instruction_builder"
require_relative "baton/engine/logger"
require_relative "baton/engine/piece_engine"

module Baton
  VERSION = "0.1.0"

  # Root directory of the gem (for locating bundled config files)
  def self.root
    File.expand_path("..", __dir__)
  end

  # Register built-in providers
  def self.setup!
    Providers::Registry.clear!
    Providers::Registry.register("claude", Providers::ClaudeProvider.new)
    Providers::Registry.register("codex", Providers::CodexProvider.new)
  end
end
