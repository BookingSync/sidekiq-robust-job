class SidekiqRobustJob
  module SidekiqJobExtensions
    extend ActiveSupport::Concern

    included do
      class << self
        alias_method :original_perform_async, :perform_async
        alias_method :original_perform_in, :perform_in
        alias_method :original_perform_at, :perform_at
        alias_method :original_set, :set
      end

      def self.perform_async(*arguments)
        SidekiqRobustJob.perform_async(self, *arguments)
      end

      def self.perform_in(interval, *arguments)
        SidekiqRobustJob.perform_in(self, interval, *arguments)
      end

      def self.perform_at(time, *arguments)
        SidekiqRobustJob.perform_at(self, time, *arguments)
      end

      def self.set(options = {})
        SidekiqRobustJob.set(self, options)
      end
    end

    def perform(job_id)
      SidekiqRobustJob.perform(job_id)
    end
  end
end
