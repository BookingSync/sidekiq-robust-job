# Changelog

## master

- Fix `enqueue_conflict_resolution_strategies` to work well with `until_executing` strategy. Handles corner case when job is being processed, yet we can't enqueue another one

## 0.2.0
- Introduce `persist_self_dropped_jobs` config option

## 0.1.0
- Initial release
