class SidekiqRobustJob
  class UniquenessStrategy
    class Base
      attr_reader :locker, :lock_ttl_proc, :jobs_repository, :memory_monitor
      private     :locker, :lock_ttl_proc, :jobs_repository, :memory_monitor

      def initialize(locker:, lock_ttl_proc:,  jobs_repository:, memory_monitor:)
        @locker = locker
        @lock_ttl_proc = lock_ttl_proc
        @jobs_repository = jobs_repository
        @memory_monitor = memory_monitor
      end

      def execute(_job)
        raise "implement me"
      end

      private

      def perform_job_and_finalize(job)
        begin
          job.call
        rescue StandardError => error
          job.failed(error)
          jobs_repository.save(job)
          raise
        end

        job.completed(memory_monitor: memory_monitor)
        jobs_repository.save(job)
      end

      def drop_unprocessed_jobs(job)
        jobs_repository.drop_unprocessed_jobs_by_digest(
          dropped_by_job_id: job.id,
          digest: job.digest,
          exclude_id: job.id
        )
      end

      def lock(job)
        locker.lock(job.digest, lock_ttl_proc.call(job)) { |locked| yield locked }
      end
    end
  end
end
