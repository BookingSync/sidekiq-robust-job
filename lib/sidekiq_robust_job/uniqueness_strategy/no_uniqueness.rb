class SidekiqRobustJob
  class UniquenessStrategy
    class NoUniqueness < SidekiqRobustJob::UniquenessStrategy::Base
      def execute(job)
        perform_job_and_finalize(job)
      end
    end
  end
end
