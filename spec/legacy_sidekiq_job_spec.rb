RSpec.describe LegacySidekiqJob, :freeze_time, type: :model do
  describe "#failed" do
    subject(:failed) { job.failed(error, clock: clock) }

    let(:job) { described_class.new(job_class: job_class, attempts: attempts) }
    let(:job_class) { "LegacySidekiqJobFailedSpecTestJob" }
    let(:attempts) { 1 }
    let(:clock) { double(now: current_time) }
    let(:current_time) { Time.current }
    let(:error) { StandardError.new("something went wrong") }

    before do
      stub_const(job_class, Class.new do
        include Sidekiq::Worker
      end)
    end

    it "does not have a next_retry_at attribute to track" do
      expect(job).not_to have_attribute(:next_retry_at)
    end

    it "does not raise" do
      expect { failed }.not_to raise_error
    end

    it { is_expected_block.to change { job.error_type }.from(nil).to("StandardError") }
    it { is_expected_block.to change { job.error_message }.from(nil).to("something went wrong") }
    it { is_expected_block.to change { job.failed_at }.from(nil).to(current_time) }
  end

  describe "#completed" do
    subject(:completed) { job.completed(memory_monitor: memory_monitor, clock: clock) }

    let(:job) do
      described_class.new(memory_usage_before_processing_in_megabytes: 50.0, dropped_at: Time.now,
        dropped_by_job_id: 5, error_type: "StandardError", error_message: "error", failed_at: Time.now)
    end
    let(:clock) { double(now: current_time) }
    let(:current_time) { Time.current }
    let(:memory_monitor) { double(mb: 100.1) }

    it "does not raise" do
      expect { completed }.not_to raise_error
    end

    it { is_expected_block.to change { job.completed_at }.from(nil).to(current_time) }
    it { is_expected_block.to change { job.failed_at }.to(nil) }
  end

  describe "#execute, end to end through a real failure" do
    subject(:execute) { job.execute }

    let(:job) do
      described_class.create!(job_class: failing_job_class, arguments: [], enqueued_at: Time.now,
        digest: "legacy-digest", uniqueness_strategy: "no_uniqueness", queue: "default",
        enqueue_conflict_resolution_strategy: "do_nothing")
    end
    let(:failing_job_class) { "LegacySidekiqJobExecuteFailureTestJob" }

    before do
      stub_const(failing_job_class, Class.new do
        include Sidekiq::Worker
        include SidekiqRobustJob::SidekiqJobExtensions

        def call
          raise "boom"
        end
      end)
    end

    it "still records the failure, without ever touching next_retry_at" do
      expect {
        execute
      }.to raise_error("boom")

      expect(job.reload.failed_at).to be_present
    end
  end
end
