class SidekiqRobustJob
  class MissedJobsScheduler
    attr_reader :serializer, :scheduled_jobs_repository
    private     :serializer, :scheduled_jobs_repository

    def initialize(cron:, scheduled_jobs_repository:, job_class:)
      @serializer = MissedJobSerializer.new(cron, job_class)
      @scheduled_jobs_repository = scheduled_jobs_repository
    end

    def schedule
      scheduled_jobs_repository.new(serializer.serialize).tap do |job|
        if job.valid?
          job.save
        else
          raise_invalid_job(job)
        end
      end
    end

    private

    def raise_invalid_job(job)
      errors = job.errors.join(",")
      raise "could not save job: #{errors}"
    end

    class MissedJobSerializer
      NAME = "SidekiqRobustJob - MissedJobsScheduler".freeze
      private_constant :NAME

      attr_reader :cron, :job_class
      private     :cron, :job_class

      def initialize(cron, job_class)
        @cron = cron
        @job_class = job_class
      end

      def serialize
        {
          name: name,
          cron: cron,
          class: job_class,
        }
      end

      private

      def name
        NAME
      end
    end
    private_constant :MissedJobSerializer
  end
end
