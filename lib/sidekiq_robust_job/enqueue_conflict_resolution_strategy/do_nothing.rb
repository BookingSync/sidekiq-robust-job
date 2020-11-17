class SidekiqRobustJob
  class EnqueueConflictResolutionStrategy
    class DoNothing < SidekiqRobustJob::EnqueueConflictResolutionStrategy::Base
      def execute(_job)
      end
    end
  end
end
