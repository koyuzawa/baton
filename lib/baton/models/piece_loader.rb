# frozen_string_literal: true

require "yaml"
require_relative "types"

module Baton
  module Models
    # Parses a piece YAML file into a PieceConfig.
    module PieceLoader
      module_function

      def load_file(path)
        raw = YAML.safe_load(File.read(path), permitted_classes: [Symbol])
        parse(raw)
      end

      def parse(raw)
        movements = {}

        (raw["movements"] || []).each do |m|
          rules = (m["rules"] || []).map.with_index do |r, idx|
            Rule.new(
              tag: m["name"].upcase,
              index: idx,
              condition: r["condition"],
              next_movement: r["next"]
            )
          end

          movement = Movement.new(
            name: m["name"],
            provider: m["provider"],
            persona: m["persona"],
            prompt: m["prompt"],
            tools: m["tools"],
            sandbox: m["sandbox"],
            max_turns: m["max_turns"] || 20,
            rules: rules
          )
          movements[m["name"]] = movement
        end

        PieceConfig.new(
          name: raw["name"],
          task: raw["task"],
          movements: movements,
          start: raw["start"] || movements.keys.first
        )
      end
    end
  end
end
