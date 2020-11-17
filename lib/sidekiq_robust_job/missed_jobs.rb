require "forwardable"

class SidekiqRobustJob
  class MissedJobs
    include Enumerable
    extend Forwardable

    def_delegator :all, :each

    attr_reader :jobs_repository, :missed_job_policy
    private     :jobs_repository, :missed_job_policy

    def initialize(jobs_repository:, missed_job_policy:)
      @jobs_repository = jobs_repository
      @missed_job_policy = missed_job_policy
    end

    def all
      @all ||= jobs_repository.missed_jobs(missed_job_policy: missed_job_policy)
    end

    def invoke
      each(&:reschedule)
    end
  end
end
