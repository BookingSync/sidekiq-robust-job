RSpec.describe SidekiqRobustJob::UniquenessStrategy do
  describe ".no_uniqueness" do
    subject(:no_uniqueness) { described_class.no_uniqueness }

    it { is_expected.to eq :no_uniqueness }
  end

  describe ".until_executing" do
    subject(:until_executing) { described_class.until_executing }

    it { is_expected.to eq :until_executing }
  end

  describe ".until_executed" do
    subject(:until_executed) { described_class.until_executed }

    it { is_expected.to eq :until_executed }
  end

  describe ".while_executing" do
    subject(:while_executing) { described_class.while_executing }

    it { is_expected.to eq :while_executing }
  end

  describe "#resolve" do
    subject(:resolve) { uniqueness_strategy.resolve(strategy) }

    let(:uniqueness_strategy) do
      described_class.new(locker: double, lock_ttl_proc: double, jobs_repository: double, memory_monitor: double)
    end

    context "when strategy is 'no_uniqueness'" do
      let(:strategy) { "no_uniqueness" }

      it { is_expected.to be_a SidekiqRobustJob::UniquenessStrategy::NoUniqueness }
    end

    context "when strategy is 'until_executing'" do
      let(:strategy) { :until_executing }

      it { is_expected.to be_a SidekiqRobustJob::UniquenessStrategy::UntilExecuting }
    end

    context "when strategy is 'until_executed'" do
      let(:strategy) { "until_executed" }

      it { is_expected.to be_a SidekiqRobustJob::UniquenessStrategy::UntilExecuted }
    end

    context "when strategy is 'while_executing'" do
      let(:strategy) { "while_executing" }

      it { is_expected.to be_a SidekiqRobustJob::UniquenessStrategy::WhileExecuting }
    end

    context "when strategy is something else" do
      let(:strategy) { "unknown" }

      it { is_expected_block.to raise_error "unknown uniqueness strategy: #{strategy}" }
    end
  end
end
