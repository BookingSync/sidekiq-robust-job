class SidekiqRobustJob
  class EnqueueConflictResolutionStrategy
    class Base
      attr_reader :jobs_repository, :clock
      private     :jobs_repository, :clock

      def initialize(jobs_repository:, clock:)
        @jobs_repository = jobs_repository
        @clock = clock
      end

      def execute(_job)
        raise "implement me"
      end
    end
  end
end
