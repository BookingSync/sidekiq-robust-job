class SidekiqRobustJob
  class MissedJobPolicy
    DEFAULT_GRACE_PERIOD = 900 # 15 minutes
    private_constant :DEFAULT_GRACE_PERIOD

    def initialize(grace_period: DEFAULT_GRACE_PERIOD)
      @grace_period = grace_period
    end

    def call(job)
      Time.current > (due_at(job) + grace_period)
    end

    private

    attr_reader :grace_period

    def due_at(job)
      [job.execute_at, job.created_at, job.next_retry_at].compact.max
    end
  end
end
