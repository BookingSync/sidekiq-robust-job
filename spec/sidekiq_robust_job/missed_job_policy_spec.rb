RSpec.describe SidekiqRobustJob::MissedJobPolicy, :freeze_time do
  subject(:call) { policy.call(job) }

  let(:policy) { described_class.new(grace_period: grace_period) }
  let(:grace_period) { 15.minutes }

  context "when execute_at is the most recent value" do
    context "when still within the grace period" do
      let(:job) { double(:job, execute_at: 10.minutes.ago, created_at: 1.hour.ago, next_retry_at: 2.hours.ago) }

      it { is_expected.to eq false }
    end

    context "when past the grace period" do
      let(:job) { double(:job, execute_at: 16.minutes.ago, created_at: 1.hour.ago, next_retry_at: 2.hours.ago) }

      it { is_expected.to eq true }
    end
  end

  context "when execute_at is nil and created_at is the most recent value" do
    context "when still within the grace period" do
      let(:job) { double(:job, execute_at: nil, created_at: 10.minutes.ago, next_retry_at: nil) }

      it { is_expected.to eq false }
    end

    context "when past the grace period" do
      let(:job) { double(:job, execute_at: nil, created_at: 16.minutes.ago, next_retry_at: nil) }

      it { is_expected.to eq true }
    end
  end

  context "when execute_at, created_at, and next_retry_at are all present but created_at is the most recent value" do
    let(:job) { double(:job, execute_at: 2.hours.ago, created_at: 16.minutes.ago, next_retry_at: 3.hours.ago) }

    it { is_expected.to eq true }
  end

  context "when next_retry_at is present and is the most recent value" do
    context "when still within the grace period" do
      let(:job) { double(:job, execute_at: 1.hour.ago, created_at: 2.hours.ago, next_retry_at: 10.minutes.ago) }

      it { is_expected.to eq false }
    end

    context "when past the grace period" do
      let(:job) { double(:job, execute_at: 1.hour.ago, created_at: 2.hours.ago, next_retry_at: 16.minutes.ago) }

      it { is_expected.to eq true }
    end
  end

  context "with a custom grace_period" do
    let(:grace_period) { 1.hour }

    context "when still within the grace period" do
      let(:job) { double(:job, execute_at: 16.minutes.ago, created_at: 1.hour.ago, next_retry_at: nil) }

      it { is_expected.to eq false }
    end

    context "when past the grace period" do
      let(:job) { double(:job, execute_at: (1.hour + 1.minute).ago, created_at: 2.hours.ago, next_retry_at: nil) }

      it { is_expected.to eq true }
    end
  end
end
