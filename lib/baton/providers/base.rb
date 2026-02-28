# frozen_string_literal: true

require_relative "../models/types"

module Baton
  module Providers
    # Base class for all providers.
    # Subclasses must implement #call(prompt, options) → AgentResponse.
    class Base
      attr_reader :name

      def initialize(name)
        @name = name
      end

      # @param prompt [String] the prompt to send
      # @param options [Hash] provider-specific options
      #   :system_prompt, :tools, :sandbox, :max_turns, :session_id, :working_dir
      # @return [Baton::Models::AgentResponse]
      def call(prompt, options = {})
        raise NotImplementedError, "#{self.class}#call must be implemented"
      end
    end

    # Global registry for provider instances.
    module Registry
      @providers = {}

      module_function

      def register(key, provider)
        @providers[key.to_s] = provider
      end

      def fetch(key)
        @providers.fetch(key.to_s) do
          raise ArgumentError, "Unknown provider: #{key}. Registered: #{@providers.keys.join(', ')}"
        end
      end

      def registered?(key)
        @providers.key?(key.to_s)
      end

      def clear!
        @providers.clear
      end

      def keys
        @providers.keys
      end
    end
  end
end
