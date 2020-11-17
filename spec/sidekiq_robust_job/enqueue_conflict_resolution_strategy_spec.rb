RSpec.describe SidekiqRobustJob::EnqueueConflictResolutionStrategy do
  describe ".do_nothing" do
    subject(:do_nothing) { described_class.do_nothing }

    it { is_expected.to eq :do_nothing }
  end

  describe ".drop_self" do
    subject(:drop_self) { described_class.drop_self }

    it { is_expected.to eq :drop_self }
  end

  describe ".replace" do
    subject(:replace) { described_class.replace }

    it { is_expected.to eq :replace }
  end

  describe "#resolve" do
    subject(:resolve) { enqueue_conflict_resolution_strategy.resolve(strategy) }

    let(:enqueue_conflict_resolution_strategy) do
      described_class.new(jobs_repository: double, clock: double)
    end

    context "when strategy is 'do_nothing'" do
      let(:strategy) { "do_nothing" }

      it { is_expected.to be_a SidekiqRobustJob::EnqueueConflictResolutionStrategy::DoNothing }
    end

    context "when strategy is 'drop_self'" do
      let(:strategy) { :drop_self }

      it { is_expected.to be_a SidekiqRobustJob::EnqueueConflictResolutionStrategy::DropSelf }
    end

    context "when strategy is 'replace'" do
      let(:strategy) { "replace" }

      it { is_expected.to be_a SidekiqRobustJob::EnqueueConflictResolutionStrategy::Replace }
    end

    context "when strategy is something else" do
      let(:strategy) { "unknown" }

      it { is_expected_block.to raise_error "unknown enqueue conflict resolution strategy: #{strategy}" }
    end
  end
end
