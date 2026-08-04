RSpec.describe SidekiqRobustJob::MissedJobs do
  describe "#all" do
    subject(:all) { missed_jobs.all }

    let(:missed_jobs) do
      described_class.new(jobs_repository: repository, missed_job_policy: missed_job_policy,
        repository_method: repository_method)
    end
    let(:repository_method) { :missed_jobs }
    let(:repository) do
      double(:repository, missed_jobs: [missed_job], missed_jobs_including_retries: [other_missed_job])
    end
    let(:missed_job_policy) { double(:missed_job_policy) }
    let(:missed_job) { double(:missed_job) }
    let(:other_missed_job) { double(:other_missed_job) }

    it "returns missed jobs from the repo" do
      expect(all).to eq [missed_job]
    end

    context "when repository_method is not provided" do
      let(:missed_jobs) { described_class.new(jobs_repository: repository, missed_job_policy: missed_job_policy) }

      it "defaults to calling :missed_jobs on the repository" do
        expect(all).to eq [missed_job]
      end
    end

    context "when a different repository_method is configured" do
      let(:repository_method) { :missed_jobs_including_retries }

      it "calls the configured method on the repository instead" do
        expect(all).to eq [other_missed_job]
      end
    end
  end

  describe "#invoke" do
    subject(:invoke) { missed_jobs.invoke }

    let(:missed_jobs) { described_class.new(jobs_repository: repository, missed_job_policy: missed_job_policy) }
    let(:repository) do
      Class.new do
        attr_reader :jobs
        private     :jobs

        def initialize(jobs)
          @jobs = jobs
        end

        def missed_jobs(missed_job_policy:)
          jobs.select { |job| missed_job_policy.call(job) }
        end
      end.new([missed_job_1, missed_job_2])
    end
    let(:missed_job_policy) { ->(job) { job.id == 1 } }
    let(:missed_job_1) do
      Class.new do
        def rescheduled?
          @rescheduled
        end

        def reschedule
          @rescheduled = true
        end

        def id
          1
        end
      end.new
    end
    let(:missed_job_2) do
      Class.new do
        def rescheduled?
          @rescheduled
        end

        def reschedule
          @rescheduled = true
        end

        def id
          2
        end
      end.new
    end

    it "reschedules all missed jobs" do
      expect {
        invoke
      }.to change { missed_job_1.rescheduled? }.to(true)
      .and avoid_changing { missed_job_2.rescheduled? }
    end
  end
end
