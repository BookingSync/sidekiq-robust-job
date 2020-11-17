RSpec.describe SidekiqRobustJob::UniquenessStrategy::UntilExecuted do
  describe "#execute" do
    subject(:execute) { strategy.execute(job) }

    let(:strategy) do
      described_class.new(
        locker: locker,
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
    let!(:job) do
      create(:sidekiq_job, job_class: SidekiqRobustJobUntilExecutedTestJob, arguments: [argument],
        memory_usage_before_processing_in_megabytes: 50, digest: digest)
    end
    let!(:job_2) do
      create(:sidekiq_job, job_class: SidekiqRobustJobUntilExecutedTestJob, arguments: [argument],
        memory_usage_before_processing_in_megabytes: 50, digest: digest)
    end
    let!(:job_3) do
      create(:sidekiq_job, job_class: SidekiqRobustJobUntilExecutedTestJob, arguments: [argument],
        memory_usage_before_processing_in_megabytes: 50, digest: digest)
    end
    let!(:job_4) do
      create(:sidekiq_job, job_class: SidekiqRobustJobUntilExecutedTestJob, arguments: [argument],
        memory_usage_before_processing_in_megabytes: 50, digest: "other")
    end
    let(:digest) { "123abc" }
    let(:locker) do
      Class.new do
        attr_reader :successful_lock, :digest, :ttl

        def initialize(successful_lock:)
          @successful_lock = successful_lock
          @digest = nil
          @ttl = ttl
        end

        def lock(digest, ttl)
          @digest = digest
          @ttl = ttl
          yield successful_lock
        end
      end.new(successful_lock: successful_lock)
    end
    let(:successful_lock) { true }

    class SidekiqJobSentinelForUntilExecutedTest
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
    class SidekiqRobustJobUntilExecutedTestJob
      include Sidekiq::Worker
      include SidekiqRobustJob::SidekiqJobExtensions

      def call(argument)
        SidekiqJobSentinelForUntilExecutedTest.call(argument)
      end
    end
    let(:argument) { "value" }

    around do |example|
      SidekiqJobSentinelForUntilExecutedTest.reset

      example.run

      SidekiqJobSentinelForUntilExecutedTest.reset
    end

    context "on success" do
      it "executes the actual Sidekiq job" do
        expect {
          execute
        }.to change { SidekiqJobSentinelForUntilExecutedTest.called? }.from(false).to(true)
        .and change { SidekiqJobSentinelForUntilExecutedTest.argument }.from(nil).to(argument)
      end

      it "sets timestamp attributes and memory usage" do
        expect {
          execute
        }.to change { job.reload.completed_at }
        .and change { job.memory_usage_after_processing_in_megabytes }
        .and change { job.memory_usage_change_in_megabytes }
      end

      it "uses lock" do
        expect {
          execute
        }.to change { locker.digest }.to(job.digest)
        .and change { locker.ttl }.to(job)
      end

      it "drops other jobs with the same digest" do
        expect {
          execute
        }.to avoid_changing { job.reload.dropped_at }
        .and avoid_changing { job.dropped_by_job_id }
        .and change { job_2.reload.dropped_at }
        .and change { job_2.dropped_by_job_id }.from(nil).to(job.id)
        .and change { job_3.reload.dropped_at }
        .and change { job_3.dropped_by_job_id }.from(nil).to(job.id)
        .and avoid_changing { job_4.reload.dropped_at }
        .and avoid_changing { job_4.dropped_by_job_id }
      end

      it "drops other jobs with the same digest after performing the job" do
        expect(strategy).to receive(:perform_job_and_finalize).with(job).ordered.and_call_original
        expect(strategy).to receive(:drop_unprocessed_jobs).with(job).ordered.and_call_original

        execute
      end
    end

    context "on semi-failure when the lock was not successfully acquired" do
      let(:successful_lock) { false }

      it "does not execute the actual Sidekiq job" do
        expect {
          execute
        }.to avoid_changing { SidekiqJobSentinelForUntilExecutedTest.called? }
        .and avoid_changing { SidekiqJobSentinelForUntilExecutedTest.argument }
      end

      it "does not set timestamp attributes and memory usage" do
        expect {
          execute
        }.to avoid_changing { job.reload.completed_at }
        .and avoid_changing { job.memory_usage_after_processing_in_megabytes }
        .and avoid_changing { job.memory_usage_change_in_megabytes }
      end

      it "does not drop other jobs with the same digest" do
        expect {
          execute
        }.to avoid_changing { job.reload.dropped_at }
        .and avoid_changing { job_2.reload.dropped_at }
        .and avoid_changing { job_3.reload.dropped_at }
        .and avoid_changing { job_4.reload.dropped_at }
      end

      it "uses lock" do
        expect {
          execute
        }.to change { locker.digest }.to(job.digest)
        .and change { locker.ttl }.to(job)
      end

      it "reschedules job" do
        expect(SidekiqRobustJobUntilExecutedTestJob).not_to have_enqueued_sidekiq_job(job.id)

        execute

        expect(SidekiqRobustJobUntilExecutedTestJob).to have_enqueued_sidekiq_job(job.id).in(5.seconds)
      end
    end

    context "on failure when the exception is raised" do
      before do
        allow(SidekiqJobSentinelForUntilExecutedTest).to receive(:call) { raise StandardError.new("whoops") }
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

      it "uses lock" do
        expect {
          execute rescue nil
        }.to change { locker.digest }.to(job.digest)
        .and change { locker.ttl }.to(job)
      end
    end
  end
end
