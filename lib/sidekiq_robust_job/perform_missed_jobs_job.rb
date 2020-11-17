class SidekiqRobustJob
  class PerformMissedJobsJob
    include Sidekiq::Worker

    def perform
      SidekiqRobustJob::DependenciesContainer["missed_jobs"].invoke
    end
  end
end
