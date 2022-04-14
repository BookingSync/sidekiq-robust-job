require "sidekiq/robust/job/version"
require "sidekiq_robust_job/configuration"
require "sidekiq_robust_job/dependencies_container"
require "sidekiq_robust_job/digest_generator"
require "sidekiq_robust_job/enqueue_conflict_resolution_strategy"
require "sidekiq_robust_job/enqueue_conflict_resolution_strategy/base"
require "sidekiq_robust_job/enqueue_conflict_resolution_strategy/do_nothing"
require "sidekiq_robust_job/enqueue_conflict_resolution_strategy/drop_self"
require "sidekiq_robust_job/enqueue_conflict_resolution_strategy/replace"
require "sidekiq_robust_job/missed_jobs"
require "sidekiq_robust_job/missed_jobs_scheduler"
require "sidekiq_robust_job/model"
require "sidekiq_robust_job/perform_missed_jobs_job"
require "sidekiq_robust_job/repository"
require "sidekiq_robust_job/setter_proxy_job"
require "sidekiq_robust_job/sidekiq_job_extensions"
require "sidekiq_robust_job/sidekiq_job_manager"
require "sidekiq_robust_job/uniqueness_strategy"
require "sidekiq_robust_job/uniqueness_strategy/base"
require "sidekiq_robust_job/uniqueness_strategy/no_uniqueness"
require "sidekiq_robust_job/uniqueness_strategy/until_executed"
require "sidekiq_robust_job/uniqueness_strategy/until_executing"
require "sidekiq_robust_job/uniqueness_strategy/while_executing"
require "sidekiq/cron/job"
require "sidekiq"
require "active_support/concern"

class SidekiqRobustJob
  def self.configuration
    @configuration ||= SidekiqRobustJob::Configuration.new
  end

  def self.configure
    yield configuration
  end

  def self.perform_async(job_class, *arguments)
    sidekiq_job_manager.perform_async(job_class, *arguments)
  end

  def self.perform_in(job_class, interval, *arguments)
    sidekiq_job_manager.perform_in(job_class, interval, *arguments)
  end

  def self.perform_at(job_class, interval, *arguments)
    sidekiq_job_manager.perform_at(job_class, interval, *arguments)
  end

  def self.set(job_class, options)
    sidekiq_job_manager.set(job_class, options)
  end

  def self.perform(job_id)
    sidekiq_job_manager.perform(job_id)
  end

  def self.schedule_missed_jobs_handling
    SidekiqRobustJob::DependenciesContainer["missed_jobs_scheduler"].schedule
  end

  def self.sidekiq_job_manager
    SidekiqRobustJob::DependenciesContainer["sidekiq_job_manager"]
  end
  private_class_method :sidekiq_job_manager
end
