FactoryBot.define do
  factory :sidekiq_job do
    job_class { "JobName" }
    enqueued_at { Time.now }
    arguments { [] }
    digest { "123abc" }
    uniqueness_strategy { "no_uniqueness" }
    queue { "default" }
    enqueue_conflict_resolution_strategy { "do_nothing" }
  end
end
