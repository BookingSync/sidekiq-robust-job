class SidekiqRobustJob
  class UniquenessStrategy
    def self.no_uniqueness
      :no_uniqueness
    end

    def self.until_executing
      :until_executing
    end

    def self.until_executed
      :until_executed
    end

    def self.while_executing
      :while_executing
    end

    attr_reader :locker, :lock_ttl_proc, :jobs_repository, :memory_monitor
    private     :locker, :lock_ttl_proc, :jobs_repository, :memory_monitor

    def initialize(locker:, lock_ttl_proc:, jobs_repository:, memory_monitor:)
      @locker = locker
      @lock_ttl_proc = lock_ttl_proc
      @jobs_repository = jobs_repository
      @memory_monitor = memory_monitor
    end

    def resolve(strategy)
      case strategy.to_sym
      when SidekiqRobustJob::UniquenessStrategy.no_uniqueness
        SidekiqRobustJob::UniquenessStrategy::NoUniqueness.new(
          locker: locker,
          lock_ttl_proc: lock_ttl_proc,
          jobs_repository: jobs_repository,
          memory_monitor: memory_monitor
        )
      when SidekiqRobustJob::UniquenessStrategy.until_executing
        SidekiqRobustJob::UniquenessStrategy::UntilExecuting.new(
          locker: locker,
          lock_ttl_proc: lock_ttl_proc,
          jobs_repository: jobs_repository,
          memory_monitor: memory_monitor
        )
      when SidekiqRobustJob::UniquenessStrategy.until_executed
        SidekiqRobustJob::UniquenessStrategy::UntilExecuted.new(
          locker: locker,
          lock_ttl_proc: lock_ttl_proc,
          jobs_repository: jobs_repository,
          memory_monitor: memory_monitor
        )
      when SidekiqRobustJob::UniquenessStrategy.while_executing
        SidekiqRobustJob::UniquenessStrategy::WhileExecuting.new(
          locker: locker,
          lock_ttl_proc: lock_ttl_proc,
          jobs_repository: jobs_repository,
          memory_monitor: memory_monitor
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
        "unknown uniqueness strategy: #{strategy}"
      end
    end
  end
end
