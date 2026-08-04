RSpec.describe SidekiqRobustJob::RetryDelayEstimator do
  subject(:call) { estimator.call(job_class: job_class, attempts: attempts, error: error) }

  let(:estimator) { described_class.new }
  let(:error) { StandardError.new("boom") }

  context "when the job class has no custom sidekiq_retry_in block" do
    before do
      stub_const("RetryDelayEstimatorDefaultTestJob", Class.new do
        include Sidekiq::Worker
      end)
    end
    let(:job_class) { "RetryDelayEstimatorDefaultTestJob" }

    context "with attempts: 1" do
      let(:attempts) { 1 }

      it "uses Sidekiq's default delay formula plus the max possible jitter" do
        expect(call).to eq (0**4 + 15) + (9 * 1)
      end
    end

    context "with attempts: 3" do
      let(:attempts) { 3 }

      it "uses Sidekiq's default delay formula plus the max possible jitter" do
        expect(call).to eq (2**4 + 15) + (9 * 3)
      end
    end
  end

  context "when the job class has a custom sidekiq_retry_in block" do
    before do
      stub_const("RetryDelayEstimatorRateLimitError", Class.new(StandardError))
      stub_const("RetryDelayEstimatorCustomTestJob", Class.new do
        include Sidekiq::Worker

        sidekiq_retry_in do |count, exception|
          exception.is_a?(RetryDelayEstimatorRateLimitError) ? 1.day.to_i : (count + 1) * 60
        end
      end)
    end
    let(:job_class) { "RetryDelayEstimatorCustomTestJob" }
    let(:attempts) { 2 }

    context "when the real exception changes the outcome" do
      let(:error) { RetryDelayEstimatorRateLimitError.new }

      it "passes the real exception into the block" do
        expect(call).to eq 1.day.to_i + (9 * 2)
      end
    end

    context "with a different exception" do
      let(:error) { StandardError.new("boom") }

      it "uses the block's other branch" do
        expect(call).to eq ((1 + 1) * 60) + (9 * 2)
      end
    end
  end

  context "when the custom block raises" do
    before do
      stub_const("RetryDelayEstimatorRaisingTestJob", Class.new do
        include Sidekiq::Worker

        sidekiq_retry_in { |_count, exception| exception.this_method_does_not_exist }
      end)
    end
    let(:job_class) { "RetryDelayEstimatorRaisingTestJob" }
    let(:attempts) { 1 }

    it "falls back to the default delay formula" do
      expect(call).to eq (0**4 + 15) + (9 * 1)
    end
  end

  context "when the job class cannot be resolved" do
    let(:job_class) { "RetryDelayEstimatorNonExistentJob" }
    let(:attempts) { 1 }

    it "falls back to the default delay formula" do
      expect(call).to eq (0**4 + 15) + (9 * 1)
    end
  end
end
