class SidekiqRobustJob
  class DependenciesContainer
    def self.[](method_name)
      public_send(method_name)
    end

    def self.sidekiq_job_manager
      SidekiqRobustJob::SidekiqJobManager.new(
        jobs_repository: SidekiqRobustJob::DependenciesContainer["jobs_repository"],
        clock: SidekiqRobustJob.configuration.clock,
        digest_generator: SidekiqRobustJob::DependenciesContainer["digest_generator"],
        memory_monitor: SidekiqRobustJob.configuration.memory_monitor,
        enqueue_conflict_resultion_failure_handler: SidekiqRobustJob.configuration.enqueue_conflict_resultion_failure_handler
      )
    end

    def self.jobs_repository
      SidekiqRobustJob::Repository.new(
        jobs_database: SidekiqRobustJob.configuration.sidekiq_job_model,
        clock: SidekiqRobustJob.configuration.clock
      )
    end

    def self.uniqueness_strategy_resolver
      SidekiqRobustJob::UniquenessStrategy.new(
        locker: SidekiqRobustJob.configuration.locker,
        lock_ttl_proc: SidekiqRobustJob.configuration.lock_ttl_proc,
        jobs_repository: SidekiqRobustJob::DependenciesContainer["jobs_repository"],
        memory_monitor: SidekiqRobustJob.configuration.memory_monitor
      )
    end

    def self.digest_generator
      SidekiqRobustJob::DigestGenerator.new(
        backend: SidekiqRobustJob.configuration.digest_generator_backend
      )
    end

    def self.enqueue_conflict_resolution_resolver
      SidekiqRobustJob::EnqueueConflictResolutionStrategy.new(
        jobs_repository: SidekiqRobustJob::DependenciesContainer["jobs_repository"],
        clock: SidekiqRobustJob.configuration.clock
      )
    end

    def self.setter_proxy_job
      SidekiqRobustJob::SetterProxyJob.new
    end

    def self.missed_jobs
      SidekiqRobustJob::MissedJobs.new(
        jobs_repository: SidekiqRobustJob::DependenciesContainer["jobs_repository"],
        missed_job_policy: SidekiqRobustJob.configuration.missed_job_policy
      )
    end

    def self.missed_jobs_scheduler
      SidekiqRobustJob::MissedJobsScheduler.new(
        cron: SidekiqRobustJob.configuration.missed_job_cron,
        scheduled_jobs_repository: Sidekiq::Cron::Job,
        job_class: SidekiqRobustJob::PerformMissedJobsJob
      )
    end
  end
end
