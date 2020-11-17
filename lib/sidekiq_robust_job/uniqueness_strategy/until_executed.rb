class SidekiqRobustJob
  class UniquenessStrategy
    class UntilExecuted < SidekiqRobustJob::UniquenessStrategy::Base
      def execute(job)
        lock(job) do |locked|
          if locked
            perform_job_and_finalize(job)
            drop_unprocessed_jobs(job)
          else
            job.reschedule and return
          end
        end
      end
    end
  end
end
