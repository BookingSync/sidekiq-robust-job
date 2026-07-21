# Changelog

## master

## 1.1.0
- Add opt-in support for including jobs currently retrying in the missed jobs handler: `next_retry_at` column/index, `SidekiqRobustJob::MissedJobPolicy`, `Repository#missed_jobs_including_retries`, and `config.missed_jobs_repository_method`. See README's "Missed Jobs Including Retries" section.

## 1.0.0
- Require at least ActiveRecord 7.1, support sidekiq-cron 2.x

## 0.3.0
- Fix `enqueue_conflict_resolution_strategies` to work well with `until_executing` strategy. Handles corner case when job is being processed, yet we can't enqueue another one
- Introduce `while_executing` uniqueness strategy, which is basically execution mutex - ensures only that 2 jobs are not executed in parallel, without considering enqueueing uniqueness.

## 0.2.0
- Introduce `persist_self_dropped_jobs` config option

## 0.1.0
- Initial release
