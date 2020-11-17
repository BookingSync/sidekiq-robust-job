RSpec.describe SidekiqRobustJob::MissedJobsScheduler do
  describe "#schedule" do
    subject(:schedule) { scheduler.schedule }

    let(:scheduler) do
      described_class.new(
        cron: cron,
        scheduled_jobs_repository: Sidekiq::Cron::Job,
        job_class: SidekiqRobustJob::PerformMissedJobsJob
      )
    end
    let(:cron) { "* 1 * 1 *" }

    around do |example|
      Sidekiq.redis { |redis| puts redis.flushall }

      example.run

      Sidekiq.redis { |redis| puts redis.flushall }
    end

    context "when job is valid" do
      context "when job does not exist yet" do
        let(:created_job) { Sidekiq::Cron::Job.all.last }

        it "creates a new job" do
          expect {
            schedule
          }.to change { Sidekiq::Cron::Job.count }.by(1)

          expect(created_job.cron).to eq cron
          expect(created_job.queue_name_with_prefix).to eq "default"
          expect(created_job.name).to eq "SidekiqRobustJob - MissedJobsScheduler"
          expect(created_job.klass).to eq "SidekiqRobustJob::PerformMissedJobsJob"
        end
      end

      context "when job already exists" do
        before do
          scheduler.schedule
        end

        it "does not create a new job" do
          expect {
            schedule
          }.not_to change { Sidekiq::Cron::Job.count }
        end
      end
    end

    context "when job is not valid" do
      let(:cron) { "invalid" }

      it { is_expected_block.to raise_error /could not save job/ }
    end
  end
end
