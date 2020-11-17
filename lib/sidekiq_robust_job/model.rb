class SidekiqRobustJob
  module Model
    extend ActiveSupport::Concern

    included do
      validates :job_class, :enqueued_at, :digest, :queue, presence: :true
      validates :uniqueness_strategy, inclusion: {
        in: [
          SidekiqRobustJob::UniquenessStrategy.no_uniqueness,
          SidekiqRobustJob::UniquenessStrategy.until_executing,
          SidekiqRobustJob::UniquenessStrategy.until_executed,
        ].map(&:to_s)
      }, on: :create

      validates :enqueue_conflict_resolution_strategy, inclusion: {
        in: [
          SidekiqRobustJob::EnqueueConflictResolutionStrategy.do_nothing,
          SidekiqRobustJob::EnqueueConflictResolutionStrategy.drop_self,
          SidekiqRobustJob::EnqueueConflictResolutionStrategy.replace,
        ].map(&:to_s)
      }, on: :create

      def self.save(job)
        job.save!
      end
    end

    def unprocessable?
      completed? || dropped?
    end

    def completed?
      completed_at.present?
    end

    def dropped?
      dropped_at.present?
    end

    def started(memory_monitor:, clock: SidekiqRobustJob.configuration.clock)
      self.memory_usage_before_processing_in_megabytes = memory_monitor.mb
      self.attempts += 1
      self.started_at = clock.now
    end

    def completed(memory_monitor:, clock: SidekiqRobustJob.configuration.clock)
      self.memory_usage_after_processing_in_megabytes = memory_monitor.mb
      self.memory_usage_change_in_megabytes = memory_usage_after_processing_in_megabytes - memory_usage_before_processing_in_megabytes
      self.completed_at = clock.now
      self.dropped_at = nil
      self.dropped_by_job_id = nil
      self.error_type = nil
      self.error_message = nil
      self.failed_at = nil
    end

    def failed(error, clock: SidekiqRobustJob.configuration.clock)
      self.error_type = error.class
      self.error_message = error.message
      self.failed_at = clock.now
    end

    def reschedule(job_class_resolver: Object)
      sidekiq_job = job_class_resolver.const_get(job_class)
      interval_in_seconds = sidekiq_job.sidekiq_options.fetch("reschedule_interval_in_seconds", 5)

      sidekiq_job.original_perform_in(interval_in_seconds.seconds, id)
    end

    def drop(dropped_by_job_id:, clock: SidekiqRobustJob.configuration.clock)
      self.dropped_at = clock.now
      self.dropped_by_job_id = dropped_by_job_id
    end

    def execute
      SidekiqRobustJob::DependenciesContainer["uniqueness_strategy_resolver"]
        .resolve(uniqueness_strategy)
        .execute(self)
    end

    def call(job_class_resolver: Object)
      job_class_resolver.const_get(job_class).new.call(*arguments)
    end

    def assign_sidekiq_data(execute_at:, sidekiq_jid:)
      self.execute_at = execute_at
      self.sidekiq_jid = sidekiq_jid
    end
  end
end
