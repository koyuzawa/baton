# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "baton"
  spec.version       = "0.1.0"
  spec.authors       = ["baton contributors"]
  spec.summary       = "AI agent orchestration CLI tool"
  spec.description   = "YAML-driven workflow orchestration for Claude Code and Codex CLI agents. " \
                        "Ruby implementation inspired by TAKT."
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.files         = Dir["lib/**/*", "bin/*", "config/**/*", "CLAUDE.md", "README.md", "LICENSE"]
  spec.bindir        = "bin"
  spec.executables   = ["baton"]
  spec.require_paths = ["lib"]

  spec.add_dependency "thor", "~> 1.3"
  spec.add_dependency "pastel", "~> 0.8"
end
