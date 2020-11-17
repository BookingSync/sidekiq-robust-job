RSpec.describe SidekiqRobustJob::EnqueueConflictResolutionStrategy::DoNothing do
  describe "#execute" do
    subject(:execute) { strategy.execute(job) }

    let(:strategy) { described_class.new(jobs_repository: double, clock: double) }
    let(:job) { double }

    it "does literally nothing" do
      expect {
        execute
      }.not_to raise_error
    end
  end
end
