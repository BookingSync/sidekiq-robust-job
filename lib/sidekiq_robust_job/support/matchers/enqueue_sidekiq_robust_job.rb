if Object.const_defined?("RSpec")
  RSpec::Matchers.define :enqueue_sidekiq_robust_job do |job_class|
    supports_block_expectations

    match do |block|
      robust_jobs_before = robust_jobs

      block.call

      robust_jobs_before.empty? && expected_job_after_execution_exists?
    end

    failure_message do
      "expected #{job_class} to have enqueued job with #{@args} to be executed at: #{execution_time}. " +
          "All enqueued jobs of this type are: #{formatted_sidekiq_jobs}. Perhaps the job was enqueued before or execution time didn't match?"
    end

    define_method :jobs do
      SidekiqRobustJob.configuration.sidekiq_job_model.all.to_a
    end

    define_method :sidekiq_jobs do
      job_class.jobs
    end

    define_method :formatted_sidekiq_jobs do
      sidekiq_jobs.map do |job|
        arguments = SidekiqRobustJob.configuration.sidekiq_job_model.find(job["args"].first).arguments
        "arguments: #{arguments}, at: #{job['at']}"
      end.join(";")
    end

    define_method :execution_time do
      raise "cannot use both :in and :at!" if @interval && @at

      if @interval
        Time.now.to_i + @interval
      elsif @at
        @at.to_time.to_i
      else
        Time.now.to_i
      end
    end

    define_method :expected_job_after_execution_exists? do
      robust_jobs.any? do |robust_job|
        sidekiq_jobs.any? do |sidekiq_job|
          sidekiq_job_at = sidekiq_job["at"]
          sidekiq_job["args"] == [robust_job.id] && (sidekiq_job_at.nil? || execution_time.to_i == Time.at(sidekiq_job_at).to_i)
        end
      end
    end

    define_method :robust_jobs do
      jobs.select { |job| job.job_class == job_class.to_s && job.arguments == @args }
    end

    chain :with do |*args|
      @args = Array.wrap(args)
    end

    chain :in do |interval|
      @interval = interval
    end

    chain :at do |at_time|
      @at = at_time
    end
  end
  RSpec::Matchers.define_negated_matcher :not_enqueue_sidekiq_robust_job, :enqueue_sidekiq_robust_job
end
