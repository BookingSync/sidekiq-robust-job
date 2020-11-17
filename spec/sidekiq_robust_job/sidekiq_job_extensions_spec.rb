RSpec.describe SidekiqRobustJob::SidekiqJobExtensions do
  let(:sidekiq_job_class) do
    Class.new do
      include Sidekiq::Worker
      include SidekiqRobustJob::SidekiqJobExtensions

      def call
      end
    end
  end

  it "aliases perform_async/perform_in/perform_at/set to have access to the original Sidekiq methods" do
    expect(sidekiq_job_class).to respond_to(:original_perform_async)
    expect(sidekiq_job_class).to respond_to(:original_perform_in)
    expect(sidekiq_job_class).to respond_to(:original_perform_at)
    expect(sidekiq_job_class).to respond_to(:original_set)
  end

  describe ".perform_async" do
    subject(:perform_async) { sidekiq_job_class.perform_async(*arguments) }

    let(:arguments) { [double] }

    it "delegates execution to SidekiqRobustJob" do
      expect(SidekiqRobustJob).to receive(:perform_async).with(sidekiq_job_class, *arguments)

      perform_async
    end
  end

  describe ".perform_in" do
    subject(:perform_in) { sidekiq_job_class.perform_in(interval, *arguments) }

    let(:interval) { 5.seconds }
    let(:arguments) { [double] }

    it "delegates execution to SidekiqRobustJob" do
      expect(SidekiqRobustJob).to receive(:perform_in).with(sidekiq_job_class, interval, *arguments)

      perform_in
    end
  end

  describe ".perform_at" do
    subject(:perform_at) { sidekiq_job_class.perform_at(time, *arguments) }

    let(:time) { Time.now }
    let(:arguments) { [double] }

    it "delegates execution to SidekiqRobustJob" do
      expect(SidekiqRobustJob).to receive(:perform_at).with(sidekiq_job_class, time, *arguments)

      perform_at
    end
  end

  describe ".set" do
    subject(:set) { sidekiq_job_class.set(options) }

    let(:options) do
      {
        queue: "critical"
      }
    end

    it "delegates execution to SidekiqRobustJob" do
      expect(SidekiqRobustJob).to receive(:set).with(sidekiq_job_class, options)

      set
    end
  end

  describe "#perform" do
    subject(:perform) { sidekiq_job_class.new.perform(job_id) }

    let(:job_id) { 1 }

    it "delegates execution to SidekiqRobustJob" do
      expect(SidekiqRobustJob).to receive(:perform).with(job_id)

      perform
    end
  end
end
