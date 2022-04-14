class SidekiqRobustJob
  class UniquenessStrategy
    class WhileExecuting < SidekiqRobustJob::UniquenessStrategy::Base
      def execute(job)
        lock(job) do |locked|
          if locked
            perform_job_and_finalize(job)
          else
            job.reschedule and return
          end
        end
      end
    end
  end
end
