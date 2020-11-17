class SidekiqRobustJob
  class UniquenessStrategy
    class UntilExecuting < SidekiqRobustJob::UniquenessStrategy::Base
      def execute(job)
        lock(job) do |locked|
          if locked
            drop_unprocessed_jobs(job)
          else
            job.reschedule and return
          end
        end
        perform_job_and_finalize(job)
      end
    end
  end
end
