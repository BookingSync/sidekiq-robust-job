require "bundler/setup"
require "rspec-sidekiq"
require "active_record"
require "timecop"
require "active_support/time_with_zone"
require "shoulda-matchers"
require "factory_bot_rails"
require "factories/sidekiq_jobs"
require "support/matchers/is_expected_block"
require "sidekiq-robust-job"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.around(:example, :freeze_time) do |example|
    freeze_time = example.metadata[:freeze_time]
    time_now = freeze_time == true ? Time.now.round : freeze_time
    Timecop.freeze(time_now) { example.run }
  end

  config.after(:example) do
    SidekiqJob.delete_all
  end

  config.include IsExpectedBlock
  config.include FactoryBot::Syntax::Methods

  Shoulda::Matchers.configure do |config|
    config.integrate do |with|
      with.test_framework :rspec
      with.library :active_record
      with.library :active_model
    end
  end

  database_name = "sidekiq-robust-job-test"
  ActiveRecord::Base.establish_connection(adapter: "postgresql", database: database_name)
  begin
    database = ActiveRecord::Base.connection
  rescue ActiveRecord::NoDatabaseError
    ActiveRecord::Base.establish_connection(adapter: "postgresql").connection.create_database(database_name)
    ActiveRecord::Base.establish_connection(adapter: "postgresql", database: database_name)
    database = ActiveRecord::Base.connection
  end


  database.drop_table(:sidekiq_jobs) if database.table_exists?(:sidekiq_jobs)
  database.create_table(:sidekiq_jobs) do |t|
    t.string "job_class", null: false
    t.datetime "enqueued_at", null: false
    t.jsonb "arguments", default: [], null: false
    t.text "digest", null: false
    t.string "uniqueness_strategy", null: false
    t.datetime "completed_at"
    t.datetime "dropped_at"
    t.datetime "failed_at"
    t.datetime "started_at"
    t.decimal "memory_usage_before_processing_in_megabytes"
    t.decimal "memory_usage_after_processing_in_megabytes"
    t.decimal "memory_usage_change_in_megabytes"
    t.integer "attempts", default: 0, null: false
    t.string "error_type"
    t.text "error_message"
    t.string "queue"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.bigint "dropped_by_job_id"
    t.string "enqueue_conflict_resolution_strategy"
    t.datetime "execute_at"
    t.string "sidekiq_jid"

    t.index ["completed_at"], name: "index_sidekiq_jobs_on_completed_at", using: :brin
    t.index ["created_at"], name: "index_sidekiq_jobs_on_created_at", using: :brin
    t.index ["digest"], name: "index_sidekiq_jobs_on_digest"
    t.index ["dropped_at"], name: "index_sidekiq_jobs_on_dropped_at", using: :brin
    t.index ["dropped_by_job_id"], name: "index_sidekiq_jobs_on_dropped_by_job_id"
    t.index ["enqueued_at"], name: "index_sidekiq_jobs_on_enqueued_at", using: :brin
    t.index ["failed_at"], name: "index_sidekiq_jobs_on_failed_at", using: :brin
    t.index ["job_class"], name: "index_sidekiq_jobs_on_job_class"
  end

  class SidekiqJob < ActiveRecord::Base
    include SidekiqRobustJob::Model
  end
end

RSpec::Matchers.define_negated_matcher :avoid_changing, :change
