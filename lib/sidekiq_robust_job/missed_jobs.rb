require "forwardable"

class SidekiqRobustJob
  class MissedJobs
    include Enumerable
    extend Forwardable

    def_delegator :all, :each

    attr_reader :jobs_repository, :missed_job_policy, :repository_method
    private     :jobs_repository, :missed_job_policy, :repository_method

    def initialize(jobs_repository:, missed_job_policy:, repository_method: :missed_jobs)
      @jobs_repository = jobs_repository
      @missed_job_policy = missed_job_policy
      @repository_method = repository_method
    end

    def all
      @all ||= jobs_repository.public_send(repository_method, missed_job_policy: missed_job_policy)
    end

    def invoke
      each(&:reschedule)
    end
  end
end
