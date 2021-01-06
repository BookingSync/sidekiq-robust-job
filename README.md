# SidekiqRobustJob

Make your Sidekiq jobs robust, durable and profilable - and fully take advantage of it!

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'sidekiq-robust-job'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install sidekiq-robust-job

## Usage

The primary idea behind the gem is storing jobs in Postgres, yet, still using the entire Sidekiq's ecosystem. You may call it a DelayedJob inside Sidekiq :).

That means that enqueuing every job will mean creating another record in the database that will represent a given SidekiqJob. And it is going to be the argument of the actual job in Redis.

To get started, you need a couple of things:

1. A proper model representing SidekiqJob:

You can use the following migration to create it:

``` rb
class CreateSidekiqJobs < ActiveRecord::Migration[6.0]
  def change
    create_table :sidekiq_jobs do |t|
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

      t.index ["completed_at", "failed_at", "dropped_at"], name: "index_sidekiq_jobs_on_completed_at_and_failed_at_and_dropped_at"
      t.index ["completed_at"], name: "index_sidekiq_jobs_on_completed_at", using: :brin
      t.index ["created_at"], name: "index_sidekiq_jobs_on_created_at", using: :brin
      t.index ["digest"], name: "index_sidekiq_jobs_on_digest"
      t.index ["dropped_at"], name: "index_sidekiq_jobs_on_dropped_at", using: :brin
      t.index ["dropped_by_job_id"], name: "index_sidekiq_jobs_on_dropped_by_job_id"
      t.index ["enqueued_at"], name: "index_sidekiq_jobs_on_enqueued_at", using: :brin
      t.index ["failed_at"], name: "index_sidekiq_jobs_on_failed_at", using: :brin
      t.index ["job_class"], name: "index_sidekiq_jobs_on_job_class"
    end
  end
end
```


and include `SidekiqRobustJob::Model` module in the job class:

``` rb
class SidekiqJob < ApplicationRecord
  include SidekiqRobustJob::Model
end
```


2. Adjust your job classes

You will need to include `SidekiqRobustJob::SidekiqJobExtensions` module and rename the `perform` method to `call`. When you include this module, the gem is going to override Sidekiq methods you normally use such as `perform/perform_async/perform_in/perform_at/set`, but we still need to have a method for the exection of the job, that's why we need a custom `call`. You can still use enqueuing methods (`perform_async/perform_in/perform_at/set`) exactly the same way, but the signature of `perform` will be different as it will be taking SidekiqJob's ID as an argument.


``` rb
class MyJob
  include Sidekiq::Worker
  include SidekiqRobustJob::SidekiqJobExtensions

  def call(user_id)
    User.find(user_id).do_something
  end
end
```


3. Add the proper initializer

``` rb
Rails.application.config.to_prepare do
  SidekiqRobustJob.configure do |config|
    config.memory_monitor = GetProcessMem.new
    config.clock = Time.zone
    config.sidekiq_job_model = SidekiqJob
  end
end
```

This is a minimum required initializer although there are more options available. SidekiqRobustJob tracks memory usage for all jobs and `memory_monitor` expects an interface like the one from [GetProcessMem gem](https://github.com/schneems/get_process_mem). If you don't want to use that feature, you can provide some "fake" memory monitor, like this one: `OpenStruct.new(mb: 0)` (we only care about `mb` method).

### Other features than durability

#### Enqueue Conflict Resolution Strategy

This feature is about handling a "conflict" (determined by a digest generated based on the job class and its arguments) when there is already the "same job" enqueued (i.e. same job class and arguments).

Let's say that there is already a job scheduled to be executed in 1 minute and we want to enqueue another one, exactly the same, in 5 minutes. There are 3 possible scenarios here:

1. `do_nothing` - this is a default when you don't specify anything. In this case, both jobs will be executed.
2. `drop_self` - **recommended**. The second job will be "dropped" - it will be created, marked as dropped (by assigning `dropped_at` timestamp and `dropped_by_job_id` that will be equal to own ID) and won't be enqueued to Redis. And of course, the first job will be executed just fine.
3. `replace` - The first job will be "dropped" - marked as dropped (by assigning `dropped_at` timestamp and `dropped_by_job_id` that will be equal to the new Job ID). Both jobs will be enqueued in Sidekiq itself, but the real logic behind them will be executed only for the second one (that replaced the first one). The original job will be handled by Sidekiq, but it's going to return early immediately due to the status check whether it's dropped.

If you want to use this feature, declare it with other Sidekiq options in the job:

``` rb
class MyJob
  include Sidekiq::Worker
  include SidekiqRobustJob::SidekiqJobExtensions

  sidekiq_options queue: "critical", enqueue_conflict_resolution_strategy: "drop_self"

  def call(user_id)
    User.find(user_id).do_something
  end
end
```

Keep in mind that this feature will work only when jobs are still scheduled to be executed, not when they are getting already performed. If you care about ensuring uniqueness of the execution (a mutex between jobs), take a look at Execution Uniqueness feature.

Although keep in mind that using this feature comes with some performance penalty due to the extra overhead and queries.

If you have a lot of conflicts within a short period, consider using `perform_in` instead of `perform_async` and add some random number of seconds (ideally, below 1 minute) to make it easier to apply enqueue conflict resolution strategy.

If you enqueue a lot of the same jobs (same class, same arguments) in a short period of time and `drop_self` strategy, you should consider setting `persist_self_dropped_jobs` config option to false. By default, it's true which means that even the jobs that are dropped are persisted, which might be useful for some profiling or even figuring out in the first place that you have an issue like this. However, under such circumstances this is likely to result in heavier queries fetching a lot of rows from the database, causing a high database load.    

Here is an example how to use it:


``` rb
class MyJob
  include Sidekiq::Worker
  include SidekiqRobustJob::SidekiqJobExtensions

  sidekiq_options queue: "critical", enqueue_conflict_resolution_strategy: "drop_self", 
    persist_self_dropped_jobs: false

  def call(user_id)
    User.find(user_id).do_something
  end
end
```

#### Execution Uniqueness (Mutex)

This feature is about handling a "conflict" (determined by a digest generated based on the job class and its arguments) when there is already the "same job" getting executed (i.e. same job class and arguments) at the same time.

Let's say that there is already a job scheduled to be executed just in a moment and you are enqueuing another one to be executed right now. There are 3 possible scenarios here:

1. `no_uniqueness` - this is a default when you don't specify anything. In this case, both jobs will be executed.
2. `until_executed` - One of the jobs acquires mutex using Redlock. When job is finished, it drops other pending jobs (and assigns `dropped_by_job_id` equal to the job that acquired the lock) with the same digest (based on job's class and arguments), and releases the lock. The job that failed to acquire a mutex is rescheduled (not dropped though, just to be on the safe side) and will be executed in the interval determined by `reschedule_interval_in_seconds` (5 seconds by default).
3. `until_executing` - One of the jobs acquires mutex using Redlock, it drops and assigns `dropped_by_job_id` equal to the job that acquired the lock) other pending jobs with the same digest (based on job's class and arguments) and releases the lock. And then it executes the actual logic behind the job. The job that failed to acquire a lock is rescheduled (not dropped though, just to be on the safe side) and will be executed in the interval determined by `reschedule_interval_in_seconds` (5 seconds by default).

If you want to use this feature, declare in with other Sidekiq options in the job:

``` rb
class MyJob
  include Sidekiq::Worker
  include SidekiqRobustJob::SidekiqJobExtensions

  sidekiq_options queue: "critical", uniqueness_strategy: "until_executed", reschedule_interval_in_seconds: 10

  def call(user_id)
    User.find(user_id).do_something
  end
end
```

You can use this feature together with Enqueue Conflict Resolution Strategy. Although keep in mind that using it comes with some performance penalty due to the extra overhead and queries.

Also, you need to provide the redlock handler. You can use [redlock-rb](https://github.com/leandromoreira/redlock-rb) for that and inject it in the initializer:


``` rb
Rails.application.config.to_prepare do
  SidekiqRobustJob.configure do |config|
    config.memory_monitor = GetProcessMem.new
    config.clock = Time.zone
    config.sidekiq_job_model = SidekiqJob
    config.locker = Redlock::Client.new([ENV.fetch("REDIS_URL")])
  end
end
```

You can also configure `lock_ttl_proc` setting which is used for determining TTL for the lock. By default it's 120 seconds, and for very long jobs you might want to reconsider it. You can use a custom lambda (or a service responding to `call`  method) to resolve this value based on the job's attributes as the lambda is expected to take a single argument - the job itself:

``` rb
config.lock_ttl_proc = ->(job) { somehow_determine_it_based_on_the_job(job) }
```

#### Missed Jobs Periodical Handler

Recommended especially when you don't use Sidekiq Pro's `super_fetch`. If you dequeue job from Redis and the process is killed (by OOM, for example) then good luck with having the job finished. However, if the job is stored in Postgres, this is not an issue. You can just look for the jobs that look as if they were missed and re-enqueue them. Periodically.

If you want to take advantage of this feature, just add the job to schedule (based on [sidekiq-cron](https://github.com/ondrejbartas/sidekiq-cron)):

``` rb
SidekiqRobustJob.schedule_missed_jobs_handling
```

By default, the job will be executed every 3 hours. It is going to look for the jobs created more than 3 hours ago that are still not completed or not dropped and reschedule them. You can customize both how often the job is executed and when the job should be considered to be missed:

```
config.missed_job_cron = "0 */3 * * *"
config.missed_job_policy = ->(job) { Time.current > (job.created_at + 3.hours) }
```

#### Getting More Insight About Jobs

There are a lot of things that are stored in the Postgres for each job that might give you a lot of insight about multiple things and use them for some sort of profiling:

-  `job_class` - a class representing a given job
-  `enqueued_at` - when the job was pushed to Sidekiq
-  `arguments` - arguments for the job execution (that will be passed to `call` method)
-  `digest` - a digest determined by job's class and its arguments
- `uniqueness_strategy` - an execution uniqueness strategy(mutex) to be used when executing the job
- `completed_at` - when the job was completed
- `dropped_at` - when the job was dropped
- `failed_at` - when the job failed (when the exception was raised)
- `started_at` - when the job was dequeued and started getting executed
- `memory_usage_before_processing_in_megabytes` - memory usage of the worker before the execution of the job
- `memory_usage_after_processing_in_megabytes` - memory usage of the worker after the execution of the job
- `memory_usage_change_in_megabytes` - the difference between after and before. Useful when looking for some outliers that require more memory than the others.
- `attempts` - how many times there was an attempt to execute this job. For successful ones, this is most likely going to be 1 unless there were some exceptions rased.
- `error_type` - a class of the exception if it was raised
- `error_message` - an error message coming from the exception if it was raised
- `queue` - name of the Sidekiq queue where the job was pushed to
- `dropped_by_job_id` - ID of the job that dropped this particular job
- `enqueue_conflict_resolution_strategy` - the name of the strategy for handling conflict when enqueuing the job
- `execute_at` - when the job is supposed to be executed (mostly when using `perform_in`/`perform_at`)
- `sidekiq_jid` - Sidekiq's Job ID (the one stored in Redis)

#### Neat Matcher For Testing

A nice bonus on top to make it easy to test: `enqueue_sidekiq_robust_job` matcher that can be chained with `with` (for job's arguments) and `in` or `at` (when using `perform_in` or `perform_at`).

First, make the matcher available:

``` rb
require "sidekiq_robust_job/support/matchers/enqueue_sidekiq_robust_job"
```

And use it in your specs.

When using `perform_async`:

``` rb
expect {
  call
}.to enqueue_sidekiq_robust_job(MyJob).with(user.id)
```

When using `perform_in`:

``` rb
expect {
  call
}.to enqueue_sidekiq_robust_job(MyJob).with(user.id).in(5.seconds)
```

When using `perform_at`:

``` rb
expect {
  call
}.to enqueue_sidekiq_robust_job(MyJob).with(user.id).at(5.seconds.from_now)
```


There is also a negated matcher: `not_enqueue_sidekiq_robust_job`.

### How to migrate already enqueued jobs when introducing the gem?

This might be a bit tricky. You might consider using new job classes temporarily so that the already existing jobs are performed and the new ones are getting enqueued and then use again the original class with `SidekiqRobustJob::SidekiqJobExtensions` included and `call` method defined.

You can also stop workers, iterate over all existing jobs, re-schedule them (after including the module) and delete them - it's safe because the actual job will still be there, but it will be enqueued this time with job's ID and  `call` method will be used. And you need to delete the original ones as they might have either a different `perform` method signature, or when having the same one, the argument will have a different meaning that job's ID, which can cause an unexpected behavior. This might require a downtime if you are not able to distinguish just based on the arguments of the job between the previous way of executing jobs and the new one. If you are able to, the downtime might not be required, but a lot of jobs can fail due to `perform` method's signature change. However, you can also re-enqueue these jobs and delete them from `RetrySet`.

### Maintenance

It is recommended to periodically remove old jobs for the maximum performance. [Tartarus](https://github.com/BookingSync/tartarus-rb) is a recommended approach for that.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/sidekiq-robust-job.


## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
