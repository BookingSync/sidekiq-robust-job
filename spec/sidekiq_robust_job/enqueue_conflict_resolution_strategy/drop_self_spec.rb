RSpec.describe SidekiqRobustJob::EnqueueConflictResolutionStrategy::DropSelf do
  describe "#execute" do
    subject(:execute) { strategy.execute(job) }

    let(:strategy) do
      described_class.new(
        jobs_repository: SidekiqRobustJob::DependenciesContainer["jobs_repository"],
        clock: double(now: now)
      )
    end
    let!(:job) { create(:sidekiq_job, digest: digest, dropped_at: nil, completed_at: nil) }
    let(:digest) { "123abc" }
    let!(:now) { Time.now.round }

    around do |example|
      original_sidekiq_job_model = SidekiqRobustJob.configuration.sidekiq_job_model

      SidekiqRobustJob.configure do |config|
        config.sidekiq_job_model = SidekiqJob
      end

      example.run

      SidekiqRobustJob.configure do |config|
        config.sidekiq_job_model = original_sidekiq_job_model
      end
    end

    context "when no jobs with the same digest exist that would not be dropped or completed" do
      let!(:processed_job) { create(:sidekiq_job, digest: digest, dropped_at: Time.now) }
      let!(:dropped_job) { create(:sidekiq_job, digest: digest, completed_at: Time.now) }

      it "does not drop self" do
        expect {
          execute
        }.to avoid_changing { job.dropped_at }
        .and avoid_changing { job.dropped_by_job_id }
      end
    end

    context "when is at least one job with the same digest exist that is not dropped/completed" do
      let!(:unprocessed_job) { create(:sidekiq_job, digest: digest) }

      it "drops self" do
        expect {
          execute
        }.to change { job.dropped_at }.to(now)
        .and change { job.dropped_by_job_id }.to(job.id)
      end
    end
  end
end
