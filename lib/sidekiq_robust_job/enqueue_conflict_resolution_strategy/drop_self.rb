class SidekiqRobustJob
  class EnqueueConflictResolutionStrategy
    class DropSelf < SidekiqRobustJob::EnqueueConflictResolutionStrategy::Base
      def execute(job)
        if jobs_repository.unprocessed_for_digest(job.digest, exclude_id: job.id).any?
          job.drop(dropped_by_job_id: job.id, clock: clock)
        end
      end
    end
  end
end
