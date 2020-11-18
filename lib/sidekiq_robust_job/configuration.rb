class SidekiqRobustJob
  class Configuration
    DEFAULT_MISSED_JOB_CRON_EVERY_THREE_HOURS = "0 */3 * * *".freeze

    attr_accessor :locker, :lock_ttl_proc, :memory_monitor, :clock, :digest_generator_backend, :sidekiq_job_model,
                  :missed_job_policy, :missed_job_cron

    def lock_ttl_proc=(val)
      raise ArgumentError.new("must be lambda-like object!") if !val.respond_to?(:call)
      @lock_ttl_proc = val
    end

    def lock_ttl_proc
      @lock_ttl_proc ||= ->(_job) { 120_000 }
    end

    def clock
      @clock ||= Time
    end

    def digest_generator_backend
      @digest_generator_backend ||= Digest::MD5
    end

    def sidekiq_job_model
      @sidekiq_job_model
    end

    def missed_job_policy=(val)
      raise ArgumentError.new("must be lambda-like object!") if !val.respond_to?(:call)
      @missed_job_policy = val
    end

    def missed_job_policy
      @missed_job_policy || ->(job) { Time.current > (job.created_at + 3.hours) }
    end

    def missed_job_cron=(val)
      Fugit.do_parse_cron(val)

      @missed_job_cron = val
    end

    def missed_job_cron
      @missed_job_cron || DEFAULT_MISSED_JOB_CRON_EVERY_THREE_HOURS
    end
  end
end
