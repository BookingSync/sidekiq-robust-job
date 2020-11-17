RSpec.describe SidekiqRobustJob do
  describe ".configuration" do
    subject(:configuration) { described_class.configuration }

    it { is_expected.to be_a SidekiqRobustJob::Configuration }
  end

  describe ".configure" do
    subject(:configuration) { described_class.configuration }
    subject(:configure) do
      SidekiqRobustJob.configure do |config|
        config.clock = :clock
      end
    end

    around do |example|
      original_clock = SidekiqRobustJob.configuration.clock

      example.run

      SidekiqRobustJob.configure do |config|
        config.clock = original_clock
      end
    end

    it "allows to configure dependencies" do
      expect {
        configure
      }.to change { configuration.clock }.to :clock
    end
  end

  describe ".perform_async" do
    subject(:perform_async) { described_class.perform_async(job_class, *arguments) }

    let(:job_class) { double }
    let(:arguments) { [double] }

    it "delegates execution to SidekiqJobManager" do
      expect_any_instance_of(SidekiqRobustJob::SidekiqJobManager).to receive(:perform_async)
        .with(job_class, *arguments)

      perform_async
    end
  end

  describe ".perform_in" do
    subject(:perform_in) { described_class.perform_in(job_class, interval, *arguments) }

    let(:job_class) { double }
    let(:interval) { 5.seconds }
    let(:arguments) { [double] }

    it "delegates execution to SidekiqJobManager" do
      expect_any_instance_of(SidekiqRobustJob::SidekiqJobManager).to receive(:perform_in)
        .with(job_class, interval, *arguments)

      perform_in
    end
  end

  describe ".perform_at" do
    subject(:perform_at) { described_class.perform_at(job_class, time, *arguments) }

    let(:job_class) { double }
    let(:time) { Time.now }
    let(:arguments) { [double] }

    it "delegates execution to SidekiqJobManager" do
      expect_any_instance_of(SidekiqRobustJob::SidekiqJobManager).to receive(:perform_at)
        .with(job_class, time, *arguments)

      perform_at
    end
  end

  describe ".set" do
    subject(:set) { described_class.set(job_class, options) }

    let(:job_class) { double }
    let(:options) do
      {
        queue: "critical"
      }
    end

    it "delegates execution to SidekiqJobManager" do
      expect_any_instance_of(SidekiqRobustJob::SidekiqJobManager).to receive(:set).with(job_class, options)

      set
    end
  end

  describe ".perform" do
    subject(:perform) { described_class.perform(job_id) }

    let(:job_id) { 1 }

    it "delegates execution to SidekiqJobManager" do
      expect_any_instance_of(SidekiqRobustJob::SidekiqJobManager).to receive(:perform)
        .with(job_id)

      perform
    end
  end

  describe ".schedule_missed_jobs_handling" do
    subject(:schedule_missed_jobs_handling) { described_class.schedule_missed_jobs_handling }

    around do |example|
      Sidekiq.redis { |redis| puts redis.flushall }

      example.run

      Sidekiq.redis { |redis| puts redis.flushall }
    end

    let(:created_job) { Sidekiq::Cron::Job.all.last }

    it "creates a new job" do
      expect {
        schedule_missed_jobs_handling
      }.to change { Sidekiq::Cron::Job.count }.by(1)

      expect(created_job.cron).to eq "0 */3 * * *"
      expect(created_job.queue_name_with_prefix).to eq "default"
      expect(created_job.name).to eq "SidekiqRobustJob - MissedJobsScheduler"
      expect(created_job.klass).to eq "SidekiqRobustJob::PerformMissedJobsJob"
    end
  end
end
