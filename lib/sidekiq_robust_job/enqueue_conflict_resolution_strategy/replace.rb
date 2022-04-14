class SidekiqRobustJob
  class EnqueueConflictResolutionStrategy
    class Replace < SidekiqRobustJob::EnqueueConflictResolutionStrategy::Base
      def execute(job)
        jobs_repository.drop_not_started_jobs_by_digest(
          dropped_by_job_id: job.id,
          digest: job.digest,
          exclude_id: job.id
        )
      end
    end
  end
end
