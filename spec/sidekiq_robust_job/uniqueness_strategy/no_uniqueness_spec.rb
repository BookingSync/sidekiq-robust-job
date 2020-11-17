RSpec.describe SidekiqRobustJob::UniquenessStrategy::NoUniqueness do
  describe "#execute" do
    subject(:execute) { strategy.execute(job) }

    let(:strategy) do
      described_class.new(
        locker: double,
        lock_ttl_proc: ->(value) { value },
        jobs_repository: SidekiqRobustJob::DependenciesContainer["jobs_repository"],
        memory_monitor: memory_monitor
      )
    end
    let(:memory_monitor) do
      Class.new do
        def mb
          100
        end
      end.new
    end
    let(:job) do
      create(:sidekiq_job, job_class: SidekiqRobustJobNoUniquenessTestJob, arguments: [argument],
        memory_usage_before_processing_in_megabytes: 50)
    end

    class SidekiqJobSentinelForNoUniquenessTest
      def self.called?
        !!@called
      end

      def self.argument
        @argument
      end

      def self.call(argument)
        @called = true
        @argument = argument
      end

      def self.reset
        @called = false
        @argument = nil
      end
    end
    class SidekiqRobustJobNoUniquenessTestJob
      include Sidekiq::Worker
      include SidekiqRobustJob::SidekiqJobExtensions

      def call(argument)
        SidekiqJobSentinelForNoUniquenessTest.call(argument)
      end
    end
    let(:argument) { "value" }

    around do |example|
      SidekiqJobSentinelForNoUniquenessTest.reset

      example.run

      SidekiqJobSentinelForNoUniquenessTest.reset
    end

    context "on success" do
      it "executes the actual Sidekiq job" do
        expect {
          execute
        }.to change { SidekiqJobSentinelForNoUniquenessTest.called? }.from(false).to(true)
        .and change { SidekiqJobSentinelForNoUniquenessTest.argument }.from(nil).to(argument)
      end

      it "sets timestamp attributes and memory usage" do
        expect {
          execute
        }.to change { job.reload.completed_at }
        .and change { job.memory_usage_after_processing_in_megabytes }
        .and change { job.memory_usage_change_in_megabytes }
      end
    end

    context "on failure" do
      before do
        allow(SidekiqJobSentinelForNoUniquenessTest).to receive(:call) { raise StandardError.new("whoops") }
      end

      it "raises error" do
        expect {
          execute
        }.to raise_error StandardError, "whoops"
      end

      it "sets failed_at and error_type/messages" do
        expect {
          execute rescue nil
        }.to change { job.reload.failed_at }
        .and change { job.error_type }.to("StandardError")
        .and change { job.error_message }.to("whoops")
      end

      it "does not set completed_at, memory_usage_after_processing_in_megabytes and memory_usage_change_in_megabytes" do
        expect {
          execute rescue nil
        }.to avoid_changing { job.reload.completed_at }
        .and avoid_changing { job.memory_usage_after_processing_in_megabytes }
        .and avoid_changing { job.memory_usage_change_in_megabytes }
      end
    end
  end
end
