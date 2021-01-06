class SidekiqRobustJob
  class Repository
    attr_reader :jobs_database, :clock
    private     :jobs_database, :clock

    def initialize(jobs_database:, clock:)
      @jobs_database = jobs_database
      @clock = clock
    end

    def transaction
      jobs_database.transaction { yield }
    end

    def find(id)
      jobs_database.find(id)
    end

    def save(record)
      record.save! if record.changed?
    end

    def create(attributes)
      jobs_database.create!(attributes)
    end

    def build(attributes)
      jobs_database.new(attributes)
    end

    def missed_jobs(missed_job_policy:)
      jobs_database
        .where(completed_at: nil, dropped_at: nil, failed_at: nil)
        .select { |potentially_missed_job| missed_job_policy.call(potentially_missed_job) }
    end

    def unprocessed_for_digest(digest, exclude_id:)
      jobs_database
        .where(digest: digest)
        .where(completed_at: nil)
        .where(dropped_at: nil)
        .where.not(id: exclude_id)
    end

    def drop_unprocessed_jobs_by_digest(dropped_by_job_id:, digest:, exclude_id:)
      transaction do
        unprocessed_for_digest(digest, exclude_id: exclude_id).lock!.find_each do |job|
          job.drop(dropped_by_job_id: dropped_by_job_id)
          save(job)
        end
      end
    end
  end
end
