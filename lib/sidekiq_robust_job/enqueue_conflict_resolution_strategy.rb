class SidekiqRobustJob
  class EnqueueConflictResolutionStrategy
    def self.do_nothing
      :do_nothing
    end

    def self.drop_self
      :drop_self
    end

    def self.replace
      :replace
    end

    attr_reader :jobs_repository, :clock
    private     :jobs_repository, :clock

    def initialize(jobs_repository:, clock:)
      @jobs_repository = jobs_repository
      @clock = clock
    end

    def resolve(strategy)
      case strategy.to_sym
      when SidekiqRobustJob::EnqueueConflictResolutionStrategy.do_nothing
        SidekiqRobustJob::EnqueueConflictResolutionStrategy::DoNothing.new(
          jobs_repository: jobs_repository,
          clock: clock
        )
      when SidekiqRobustJob::EnqueueConflictResolutionStrategy.drop_self
        SidekiqRobustJob::EnqueueConflictResolutionStrategy::DropSelf.new(
          jobs_repository: jobs_repository,
          clock: clock
        )
      when SidekiqRobustJob::EnqueueConflictResolutionStrategy.replace
        SidekiqRobustJob::EnqueueConflictResolutionStrategy::Replace.new(
          jobs_repository: jobs_repository,
          clock: clock
        )
      else
        raise UnknownStrategyError.new(strategy)
      end
    end

    class UnknownStrategyError < StandardError
      attr_reader :strategy
      private     :strategy

      def initialize(strategy)
        @strategy = strategy
      end

      def message
        "unknown enqueue conflict resolution strategy: #{strategy}"
      end
    end
  end
end
