RSpec.describe SidekiqRobustJob::PerformMissedJobsJob, :freeze_time do
  it { is_expected.to be_processed_in :default }

  describe "#perform" do
    subject(:perform) { described_class.new.perform }

    let(:missed_job_policy) do
      ->(job) { Time.current > (job.created_at + 1.hour) }
    end
    let!(:job_1) do
      FactoryBot.create(:sidekiq_job, job_class: JobForTestingPerformMissedJobsJob)
    end
    let!(:job_2) do
      FactoryBot.create(:sidekiq_job, job_class: JobForTestingPerformMissedJobsJob, completed_at: Time.now,
        created_at: 1.day.ago)
    end
    let!(:job_3) do
      FactoryBot.create(:sidekiq_job, job_class: JobForTestingPerformMissedJobsJob, failed_at: Time.now,
        created_at: 1.day.ago)
    end
    let!(:job_4) do
      FactoryBot.create(:sidekiq_job, job_class: JobForTestingPerformMissedJobsJob, dropped_at: Time.now,
        created_at: 1.day.ago)
    end
    let!(:job_5) do
      FactoryBot.create(:sidekiq_job, job_class: JobForTestingPerformMissedJobsJob, created_at: 55.minutes.ago)
    end
    let!(:job_6) do
      FactoryBot.create(:sidekiq_job, job_class: JobForTestingPerformMissedJobsJob, created_at: 65.minutes.ago)
    end

    class JobForTestingPerformMissedJobsJob
      include Sidekiq::Worker
      include SidekiqRobustJob::SidekiqJobExtensions

      def call
      end
    end

    around do |example|
      original_policy = SidekiqRobustJob.configuration.missed_job_policy

      SidekiqRobustJob.configure do |config|
        config.missed_job_policy = missed_job_policy
      end

      example.run

      SidekiqRobustJob.configure do |config|
        config.missed_job_policy = original_policy
      end
    end

    it "performs (reschedules) missed jobs" do
      expect(JobForTestingPerformMissedJobsJob).not_to have_enqueued_sidekiq_job(job_1.id)
      expect(JobForTestingPerformMissedJobsJob).not_to have_enqueued_sidekiq_job(job_2.id)
      expect(JobForTestingPerformMissedJobsJob).not_to have_enqueued_sidekiq_job(job_3.id)
      expect(JobForTestingPerformMissedJobsJob).not_to have_enqueued_sidekiq_job(job_4.id)
      expect(JobForTestingPerformMissedJobsJob).not_to have_enqueued_sidekiq_job(job_5.id)
      expect(JobForTestingPerformMissedJobsJob).not_to have_enqueued_sidekiq_job(job_6.id)

      perform

      expect(JobForTestingPerformMissedJobsJob).not_to have_enqueued_sidekiq_job(job_1.id)
      expect(JobForTestingPerformMissedJobsJob).not_to have_enqueued_sidekiq_job(job_2.id)
      expect(JobForTestingPerformMissedJobsJob).not_to have_enqueued_sidekiq_job(job_3.id)
      expect(JobForTestingPerformMissedJobsJob).not_to have_enqueued_sidekiq_job(job_4.id)
      expect(JobForTestingPerformMissedJobsJob).not_to have_enqueued_sidekiq_job(job_5.id)
      expect(JobForTestingPerformMissedJobsJob).to have_enqueued_sidekiq_job(job_6.id)
    end
  end
end
