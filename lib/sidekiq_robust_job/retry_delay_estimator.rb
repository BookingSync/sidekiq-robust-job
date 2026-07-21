class SidekiqRobustJob
  class RetryDelayEstimator
    DEFAULT_DELAY = ->(count) { (count**4) + 15 }
    private_constant :DEFAULT_DELAY

    def call(job_class:, attempts:, error:)
      count = attempts - 1
      delay_for(job_class, count, error) + max_jitter_for(count)
    end

    private

    def delay_for(job_class, count, error)
      job_klass = Object.const_get(job_class)
      retry_value = job_klass.sidekiq_retry_in_block&.call(count, error)
      (Integer === retry_value && retry_value > 0) ? retry_value : DEFAULT_DELAY.call(count)
    rescue
      DEFAULT_DELAY.call(count)
    end

    # Sidekiq's own jitter is `rand(10) * (count + 1)` - non-deterministic and redrawn
    # independently when Sidekiq itself schedules the retry, so we can't predict the
    # exact value. We take the max possible draw as a safe upper bound: this guarantees
    # we never call a job "missed" before the latest moment Sidekiq could still retry it.
    def max_jitter_for(count)
      9 * (count + 1)
    end
  end
end
