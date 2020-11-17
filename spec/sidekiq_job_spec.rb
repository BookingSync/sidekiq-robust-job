RSpec.describe SidekiqJob, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:job_class) }
    it { is_expected.to validate_presence_of(:enqueued_at) }
    it { is_expected.to validate_presence_of(:digest) }
    it { is_expected.to validate_presence_of(:queue) }
    it {
      is_expected.to validate_inclusion_of(:uniqueness_strategy)
        .in_array(["no_uniqueness", "until_executing", "until_executed"]).on(:create)
    }
    it {
      is_expected.to validate_inclusion_of(:enqueue_conflict_resolution_strategy)
        .in_array(["do_nothing", "drop_self", "replace"]).on(:create)
    }
  end

  describe "#unprocessable?" do
    subject(:unprocessable?) { job.unprocessable? }

    let(:job) { described_class.new(completed_at: completed_at, dropped_at: dropped_at) }

    context "when job is completed and dropped" do
      let(:completed_at) { Time.current }
      let(:dropped_at) { Time.current }

      it { is_expected.to eq true }
    end

    context "when job is completed and not dropped" do
      let(:completed_at) { Time.current }
      let(:dropped_at) { nil }

      it { is_expected.to eq true }
    end

    context "when job is not completed and dropped" do
      let(:completed_at) { nil }
      let(:dropped_at) { Time.current }

      it { is_expected.to eq true }
    end

    context "when job is not processed and not dropped" do
      let(:completed_at) { nil }
      let(:dropped_at) { nil }

      it { is_expected.to eq false }
    end
  end

  describe "#completed?" do
    subject(:completed?) { job.completed? }

    let(:job) { described_class.new(completed_at: completed_at) }

    context "when job is completed" do
      let(:completed_at) { Time.current }

      it { is_expected.to eq true }
    end

    context "when job is not completed" do
      let(:completed_at) { nil }

      it { is_expected.to eq false }
    end
  end

  describe "#dropped?" do
    subject(:dropped?) { job.dropped? }

    let(:job) { described_class.new(dropped_at: dropped_at) }

    context "when job is dropped" do
      let(:dropped_at) { Time.current }

      it { is_expected.to eq true }
    end

    context "when job is not dropped" do
      let(:dropped_at) { nil }

      it { is_expected.to eq false }
    end
  end

  describe "#started" do
    subject(:started) { job.started(memory_monitor: memory_monitor, clock: clock) }

    let(:job) { described_class.new }
    let(:clock) { double(now: current_time) }
    let(:current_time) { Time.current }
    let(:memory_monitor) { double(mb: 100.1) }

    it { is_expected_block.to change { job.memory_usage_before_processing_in_megabytes }.from(nil).to(100.1) }
    it { is_expected_block.to change { job.attempts }.from(0).to(1) }
    it { is_expected_block.to change { job.started_at }.from(nil).to(current_time) }
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

    it { is_expected_block.to change { job.memory_usage_after_processing_in_megabytes }.from(nil).to(100.1) }
    it { is_expected_block.to change { job.memory_usage_change_in_megabytes }.from(nil).to(50.1) }
    it { is_expected_block.to change { job.completed_at }.from(nil).to(current_time) }

    it { is_expected_block.to change { job.dropped_at }.to(nil) }
    it { is_expected_block.to change { job.dropped_by_job_id }.to(nil) }

    it { is_expected_block.to change { job.error_type }.to(nil) }
    it { is_expected_block.to change { job.error_message }.to(nil) }
    it { is_expected_block.to change { job.failed_at }.to(nil) }
  end

  describe "#failed" do
    subject(:failed) { job.failed(error, clock: clock) }

    let(:job) { described_class.new }
    let(:clock) { double(now: current_time) }
    let(:current_time) { Time.current }
    let(:error) { StandardError.new("something went wrong") }

    it { is_expected_block.to change { job.error_type }.from(nil).to("StandardError") }
    it { is_expected_block.to change { job.error_message }.from(nil).to("something went wrong") }
    it { is_expected_block.to change { job.failed_at }.from(nil).to(current_time) }
  end

  describe "#reschedule" do
    subject(:reschedule) { job.reschedule(job_class_resolver: job_class_resolver) }

    let(:job) { described_class.new(job_class: job_class, id: 10) }

    let(:job_class_resolver) do
      Class.new do
        def initialize(job_class)
          @job_class = job_class
        end

        def const_get(_job_class)
          @job_class
        end
      end.new(job_class)
    end

    context "when reschedule_interval_in_seconds is not set in sidekiq options" do
      let(:job_class) do
        Class.new do
          include Sidekiq::Worker
          include SidekiqRobustJob::SidekiqJobExtensions
        end
      end

      it "reschedules job to be executed in 5 seconds" do
        reschedule

        expect(job_class).to have_enqueued_sidekiq_job(job.id).in(5.seconds)
      end
    end

    context "when reschedule_interval_in_seconds is set in sidekiq options" do
      let(:job_class) do
        Class.new do
          include Sidekiq::Worker
          include SidekiqRobustJob::SidekiqJobExtensions

          sidekiq_options reschedule_interval_in_seconds: 10
        end
      end

      it "reschedules job to be executed in interval based on provided config" do
        reschedule

        expect(job_class).to have_enqueued_sidekiq_job(job.id).in(10.seconds)
      end
    end
  end

  describe "#drop" do
    subject(:drop) { job.drop(dropped_by_job_id: dropped_by_job_id, clock: clock) }

    let(:job) { described_class.new }
    let(:clock) { double(now: now) }
    let!(:now) { Time.now }
    let(:dropped_by_job_id) { 121 }

    it "assigns dropped_at and dropped_by_job_id" do
      expect {
        drop
      }.to change { job.dropped_at }.to(now)
      .and change { job.dropped_by_job_id }.to(dropped_by_job_id)
    end
  end

  describe "#execute" do
    subject(:execute) { job.execute }

    let(:job) do
      create(:sidekiq_job, job_class: SidekiqRobustJobSidekiqJobExecuteMethodTestJob, arguments: [argument],
        memory_usage_before_processing_in_megabytes: 50)
    end

    class SidekiqJobSentinelForExecuteMethod
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
    class SidekiqRobustJobSidekiqJobExecuteMethodTestJob
      include Sidekiq::Worker
      include SidekiqRobustJob::SidekiqJobExtensions

      def call(argument)
        SidekiqJobSentinelForExecuteMethod.call(argument)
      end
    end
    let(:argument) { "value" }
    let(:memory_monitor) do
      Class.new do
        def mb
          100
        end
      end.new
    end

    around do |example|
      original_clock = SidekiqRobustJob.configuration.clock
      original_memory_monitor = SidekiqRobustJob.configuration.memory_monitor

      SidekiqRobustJob.configure do |config|
        config.clock = Time.zone
        config.memory_monitor = memory_monitor
      end

      example.run

      SidekiqRobustJob.configure do |config|
        config.clock = original_clock
        config.memory_monitor = original_memory_monitor
      end
    end

    around do |example|
      SidekiqJobSentinelForExecuteMethod.reset

      example.run

      SidekiqJobSentinelForExecuteMethod.reset
    end

    it "executes the actual Sidekiq job" do
      expect {
        execute
      }.to change { SidekiqJobSentinelForExecuteMethod.called? }.from(false).to(true)
      .and change { SidekiqJobSentinelForExecuteMethod.argument }.from(nil).to(argument)
    end

    it "uses uniqueness strategy" do
      expect_any_instance_of(SidekiqRobustJob::UniquenessStrategy::NoUniqueness).to receive(:execute)
        .with(job).and_call_original

      execute
    end

    it "sets timestamp attributes, attempts and memory usage" do
      expect {
        execute
      }.to change { job.reload.completed_at }
      .and change { job.memory_usage_after_processing_in_megabytes }
      .and change { job.memory_usage_change_in_megabytes }
    end
  end

  describe "#call" do
    subject(:call) { job.call }

    let(:job) { create(:sidekiq_job, job_class: SidekiqRobustJobSidekiqJobCallMethodTestJob, arguments: [argument]) }

    class SidekiqJobSentinelForCallMethod
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
    class SidekiqRobustJobSidekiqJobCallMethodTestJob
      include Sidekiq::Worker
      include SidekiqRobustJob::SidekiqJobExtensions

      def call(argument)
        SidekiqJobSentinelForCallMethod.call(argument)
      end
    end
    let(:argument) { "value" }

    around do |example|
      SidekiqJobSentinelForCallMethod.reset

      example.run

      SidekiqJobSentinelForCallMethod.reset
    end

    it "executes the actual Sidekiq job" do
      expect {
        call
      }.to change { SidekiqJobSentinelForCallMethod.called? }.from(false).to(true)
      .and change { SidekiqJobSentinelForCallMethod.argument }.from(nil).to(argument)
    end
  end

  describe "#assign_sidekiq_data", :freeze_time do
    subject(:assign_sidekiq_data) { job.assign_sidekiq_data(execute_at: execute_at, sidekiq_jid: sidekiq_jid) }

    let(:job) { described_class.new }
    let(:execute_at) { Time.now.round }
    let(:sidekiq_jid) { "123" }

    it { is_expected_block.to change { job.sidekiq_jid }.from(nil).to("123") }
    it { is_expected_block.to change { job.execute_at }.from(nil).to(execute_at) }
  end
end
