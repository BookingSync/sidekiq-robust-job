RSpec.describe SidekiqRobustJob::Configuration do
  describe "locker" do
    subject(:locker) { configuration.locker }

    let(:configuration) { described_class.new }

    context "when 'locker' is not set" do
      it { is_expected.to eq nil }
    end

    context "when 'locker' is set" do
      let(:locker_value) { double(:locker_value) }

      before do
        configuration.locker = locker_value
      end

      it { is_expected.to eq locker_value }
    end
  end

  describe "lock_ttl_proc" do
    subject(:lock_ttl_proc) { configuration.lock_ttl_proc }

    let(:configuration) { described_class.new }

    context "when 'lock_ttl_proc' is not set" do
      it "returns a lambda taking one argument returning 120_000" do
        expect(lock_ttl_proc.call(double)).to eq 120_000
      end
    end

    context "when 'lock_ttl_proc' is set" do
      context "when it's set as a lambda-like object" do
        let(:lock_ttl_proc_value) { ->(val) { val } }

        before do
          configuration.lock_ttl_proc = lock_ttl_proc_value
        end

        it { expect(lock_ttl_proc.call("value")).to eq "value" }
      end

      context "when it's not set as a lambda-like object" do
        subject(:set_lock_ttl_proc) { configuration.lock_ttl_proc = lock_ttl_proc_value }

        let(:lock_ttl_proc_value) { double(:locker_value) }

        it "raises error" do
          expect {
            set_lock_ttl_proc
          }.to raise_error ArgumentError
        end
      end
    end
  end

  describe "memory_monitor" do
    subject(:memory_monitor) { configuration.memory_monitor }

    let(:configuration) { described_class.new }

    context "when 'memory_monitor' is not set" do
      it { is_expected.to eq nil }
    end

    context "when 'memory_monitor' is set" do
      let(:memory_monitor_value) { double(:memory_monitor_value) }

      before do
        configuration.memory_monitor = memory_monitor_value
      end

      it { is_expected.to eq memory_monitor_value }
    end
  end

  describe "clock" do
    subject(:clock) { configuration.clock }

    let(:configuration) { described_class.new }

    context "when 'clock' is not set" do
      it { is_expected.to eq Time }
    end

    context "when 'clock' is set" do
      let(:clock_value) { double(:clock_value) }

      before do
        configuration.clock = clock_value
      end

      it { is_expected.to eq clock_value }
    end
  end

  describe "digest_generator_backend" do
    subject(:digest_generator_backend) { configuration.digest_generator_backend }

    let(:configuration) { described_class.new }

    context "when 'digest_generator_backend' is not set" do
      it { is_expected.to eq Digest::MD5 }
    end

    context "when 'digest_generator_backend' is set" do
      let(:digest_generator_backend_value) { double(:digest_generator_backend_value) }

      before do
        configuration.digest_generator_backend = digest_generator_backend_value
      end

      it { is_expected.to eq digest_generator_backend_value }
    end
  end

  describe "sidekiq_job_model" do
    subject(:sidekiq_job_model) { configuration.sidekiq_job_model }

    let(:configuration) { described_class.new }

    context "when 'sidekiq_job_model' is not set" do
      it { is_expected.to eq nil }
    end

    context "when 'sidekiq_job_model' is set" do
      let(:sidekiq_job_model_value) { double(:sidekiq_job_model_value) }

      before do
        configuration.sidekiq_job_model = sidekiq_job_model_value
      end

      it { is_expected.to eq sidekiq_job_model_value }
    end
  end

  describe "missed_job_policy" do
    subject(:missed_job_policy) { configuration.missed_job_policy }

    let(:configuration) { described_class.new }

    context "when 'missed_job_policy=' is not set", :freeze_time do
      let(:job_1) { double(:job, created_at: 181.minutes.ago) }
      let(:job_2) { double(:job, created_at: 180.minutes.ago) }
      let(:job_3) { double(:job, created_at: 179.minutes.ago) }

      it "returns a lambda taking job as an argument returning true if :created_at is more than 3 hours" do
        expect(missed_job_policy.call(job_1)).to eq true
        expect(missed_job_policy.call(job_2)).to eq false
        expect(missed_job_policy.call(job_2)).to eq false
      end
    end

    context "when 'missed_job_policy' is set" do
      context "when it's set as a lambda-like object" do
        let(:missed_job_policy_value) { ->(val) { val } }

        before do
          configuration.missed_job_policy = missed_job_policy_value
        end

        it { expect(missed_job_policy.call("value")).to eq "value" }
      end

      context "when it's not set as a lambda-like object" do
        subject(:set_missed_job_policy) { configuration.missed_job_policy = missed_job_policy_value }

        let(:missed_job_policy_value) { double(:missed_job_policy_value) }

        it "raises error" do
          expect {
            set_missed_job_policy
          }.to raise_error ArgumentError
        end
      end
    end
  end

  describe "missed_job_cron" do
    subject(:missed_job_cron) { configuration.missed_job_cron }

    let(:configuration) { described_class.new }

    context "when 'missed_job_cron' is not set" do
      it "returns a default value" do
        expect(missed_job_cron).to eq "0 */3 * * *"
      end
    end

    context "when 'missed_job_cron' is set" do
      context "when it's a valid cron value" do
        let(:missed_job_cron_value) { "1 1 1 1 1" }

        before do
          configuration.missed_job_cron = missed_job_cron_value
        end

        it { is_expected.to eq missed_job_cron_value }
      end

      context "when it's not a valid cron value" do
        subject(:set_missed_job_cron_value) { configuration.missed_job_cron = missed_job_cron_value }
        let(:missed_job_cron_value) { "WTF" }

        it { is_expected_block.to raise_error ArgumentError }
      end
    end
  end
end
