class SidekiqRobustJob
  class SidekiqJobManager
    attr_reader :jobs_repository, :clock, :digest_generator, :memory_monitor
    private     :jobs_repository, :clock, :digest_generator, :memory_monitor

    def initialize(jobs_repository:, clock:, digest_generator:, memory_monitor:)
      @jobs_repository = jobs_repository
      @clock = clock
      @digest_generator = digest_generator
      @memory_monitor = memory_monitor
    end

    def perform_async(job_class, *arguments)
      job = create_job(job_class, *arguments)
      return if job.unprocessable?
      job_class.original_perform_async(job.id).tap do |sidekiq_jid|
        job.assign_sidekiq_data(execute_at: clock.now, sidekiq_jid: sidekiq_jid)
        jobs_repository.save(job)
      end
    end

    def perform_in(job_class, interval, *arguments)
      job = create_job(job_class, *arguments)
      return if job.unprocessable?
      job_class.original_perform_in(interval, job.id).tap do |sidekiq_jid|
        job.assign_sidekiq_data(execute_at: clock.now + interval, sidekiq_jid: sidekiq_jid)
        jobs_repository.save(job)
      end
    end

    def perform_at(job_class, time, *arguments)
      job = create_job(job_class, *arguments)
      return if job.unprocessable?
      job_class.original_perform_at(time, job.id).tap do |sidekiq_jid|
        job.assign_sidekiq_data(execute_at: time, sidekiq_jid: sidekiq_jid)
        jobs_repository.save(job)
      end
    end

    def set(job_class, options = {})
      SidekiqRobustJob::DependenciesContainer["setter_proxy_job"].build(job_class, options)
    end

    def perform(job_id)
      job = jobs_repository.find(job_id)
      return if job.unprocessable?

      job.started(memory_monitor: memory_monitor)
      jobs_repository.save(job)
      job.execute
    end

    private

    def create_job(job_class, *arguments)
      jobs_repository.build(
        job_class: job_class,
        arguments: Array.wrap(arguments),
        enqueued_at: clock.now,
        digest: digest_generator.generate(job_class, *arguments),
        queue: job_class.get_sidekiq_options.fetch("queue", "default"),
        uniqueness_strategy: job_class.get_sidekiq_options.fetch("uniqueness_strategy",
          SidekiqRobustJob::UniquenessStrategy.no_uniqueness),
        enqueue_conflict_resolution_strategy: job_class.get_sidekiq_options.fetch("enqueue_conflict_resolution_strategy",
          SidekiqRobustJob::EnqueueConflictResolutionStrategy.do_nothing)
      ).tap do |job|
        jobs_repository.save(job) if persist_job_immediately?(job_class)
        jobs_repository.transaction do
          resolve_potential_conflict_for_enqueueing(job)
          jobs_repository.save(job) if persist_after_resolving_conflict_for_enqueueing(job, job_class)
        end
      end
    end

    def resolve_potential_conflict_for_enqueueing(job)
      SidekiqRobustJob::DependenciesContainer["enqueue_conflict_resolution_resolver"]
        .resolve(job.enqueue_conflict_resolution_strategy)
        .execute(job)
    end

    def persist_job_immediately?(job_class)
      persist_self_dropped_jobs?(job_class)
    end

    def persist_after_resolving_conflict_for_enqueueing(job, job_class)
      return true if persist_self_dropped_jobs?(job_class)

      !job.dropped?
    end

    def persist_self_dropped_jobs?(job_class)
      job_class.get_sidekiq_options.fetch("persist_self_dropped_jobs", true)
    end
  end
end
