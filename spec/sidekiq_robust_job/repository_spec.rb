RSpec.describe SidekiqRobustJob::Repository do
  describe "#transaction" do
    subject(:transaction) { repository.transaction { sentinel.call } }

    let(:repository) { described_class.new(jobs_database: jobs_database, clock: Time) }
    let(:jobs_database) { SidekiqJob }

    let(:sentinel) do
      Class.new do
        def called?
          @called
        end

        def call
          @called = true
        end

        def reset
          @called = nil
        end
      end.new
    end

    it "delegates method call to :jobs_database" do
      expect(jobs_database).to receive(:transaction).and_call_original

      expect {
        transaction
      }.to change { sentinel.called? }.to(true)
    end
  end

  describe "#find" do
    subject(:find) { repository.find(id) }

    let(:repository) { described_class.new(jobs_database: SidekiqJob, clock: Time) }

    let(:id) { job_2.id }
    let!(:job_1) { create(:sidekiq_job) }
    let!(:job_2) { create(:sidekiq_job) }

    it "finds SidekiqJob by ID" do
      expect(find).to eq job_2
    end
  end

  describe "#save" do
    subject(:save) { repository.save(job) }

    let(:repository) { described_class.new(jobs_database: SidekiqJob, clock: Time) }

    context "when something has changed" do
      let!(:job) { build(:sidekiq_job) }

      it "persist a given SidekiqJob" do
        expect(job).to receive(:save!).and_call_original

        expect {
          save
        }.to change { job.persisted? }.from(false).to(true)
      end
    end

    context "when nothing has changed has changed" do
      let!(:job) { create(:sidekiq_job, updated_at: 1.week.ago) }

      it "does no persist a given SidekiqJob" do
        expect(job).not_to receive(:save!)

        save
      end
    end
  end

  describe "#create" do
    subject(:create_job) { repository.create(attributes) }

    let(:repository) { described_class.new(jobs_database: SidekiqJob, clock: Time) }
    let(:attributes) do
      {
        job_class: "Class",
        enqueued_at: Time.now,
        digest: "digest",
        uniqueness_strategy: "no_uniqueness",
        enqueue_conflict_resolution_strategy: "do_nothing",
        queue: "default"
      }
    end

    it "creates SidekiqJob" do
      job = nil
      expect {
        job = create_job
      }.to change { SidekiqJob.count }.by(1)

      expect(job).to be_persisted
      expect(job.job_class).to eq "Class"
      expect(job.digest).to eq "digest"
      expect(job.uniqueness_strategy).to eq "no_uniqueness"
      expect(job.enqueue_conflict_resolution_strategy).to eq "do_nothing"
      expect(job.queue).to eq "default"
    end
  end

  describe "#build" do
    subject(:build_job) { repository.build(attributes) }

    let(:repository) { described_class.new(jobs_database: SidekiqJob, clock: Time) }
    let(:attributes) do
      {
        job_class: "Class",
        enqueued_at: Time.now,
        digest: "digest",
        uniqueness_strategy: "no_uniqueness",
        enqueue_conflict_resolution_strategy: "do_nothing",
        queue: "default"
      }
    end

    it "build SidekiqJob, but does not persist it" do
      job = nil
      expect {
        job = build_job
      }.not_to change { SidekiqJob.count }

      expect(job).not_to be_persisted
      expect(job.job_class).to eq "Class"
      expect(job.digest).to eq "digest"
      expect(job.uniqueness_strategy).to eq "no_uniqueness"
      expect(job.enqueue_conflict_resolution_strategy).to eq "do_nothing"
      expect(job.queue).to eq "default"
    end
  end

  describe "#missed_jobs" do
    subject(:missed_jobs) { repository.missed_jobs(missed_job_policy: missed_jobs_policy) }

    let(:repository) { described_class.new(jobs_database: SidekiqJob, clock: Time) }
    let(:missed_jobs_policy) do
      ->(job) { Time.current > (job.created_at + 1.hour) }
    end

    let!(:job_1) { FactoryBot.create(:sidekiq_job) }
    let!(:job_2) { FactoryBot.create(:sidekiq_job, completed_at: Time.now, created_at: 1.day.ago) }
    let!(:job_3) { FactoryBot.create(:sidekiq_job, failed_at: Time.now, created_at: 1.day.ago) }
    let!(:job_4) { FactoryBot.create(:sidekiq_job, dropped_at: Time.now, created_at: 1.day.ago) }
    let!(:job_5) { FactoryBot.create(:sidekiq_job, created_at: 55.minutes.ago) }
    let!(:job_6) { FactoryBot.create(:sidekiq_job, created_at: 65.minutes.ago) }

    it "returns not completed, not dropped, not failed jobs that satisfy the provided policy" do
      expect(missed_jobs).to match_array [job_6]
    end
  end

  describe "#unprocessed_for_digest" do
    subject(:unprocessed_for_digest) do
      repository.unprocessed_for_digest(digest, exclude_id: job_6.id)
    end

    let(:repository) { described_class.new(jobs_database: SidekiqJob, clock: clock) }
    let!(:clock) { double(now: current_time) }
    let!(:current_time) { Time.current.round }
    let(:digest) { "123abc321" }
    let!(:job_1) { FactoryBot.create(:sidekiq_job, digest: digest, completed_at: nil) }
    let!(:job_2) { FactoryBot.create(:sidekiq_job, digest: digest, completed_at: nil, dropped_at: 1.day.ago) }
    let!(:job_3) { FactoryBot.create(:sidekiq_job, digest: digest, completed_at: Time.current) }
    let!(:job_4) { FactoryBot.create(:sidekiq_job, digest: "other", completed_at: Time.current) }
    let!(:job_5) { FactoryBot.create(:sidekiq_job, digest: "other_2", completed_at: nil) }
    let!(:job_6) { FactoryBot.create(:sidekiq_job, digest: digest, completed_at: nil) }

    it "returns jobs that have given digest that are not dropped or completed excluding provided ID" do
      expect(unprocessed_for_digest).to match_array [job_1]
    end
  end

  describe "#drop_unprocessed_jobs_by_digest", :freeze_time do
    subject(:drop_unprocessed_jobs_by_digest) do
      repository.drop_unprocessed_jobs_by_digest(dropped_by_job_id: 1212, digest: digest, exclude_id: job_6.id)
    end

    let(:repository) { described_class.new(jobs_database: SidekiqJob, clock: clock) }
    let!(:clock) { double(now: current_time) }
    let!(:current_time) { Time.current.round }
    let(:digest) { "123abc321" }
    let!(:job_1) { FactoryBot.create(:sidekiq_job, digest: digest, completed_at: nil) }
    let!(:job_2) { FactoryBot.create(:sidekiq_job, digest: digest, completed_at: nil, dropped_at: 1.day.ago) }
    let!(:job_3) { FactoryBot.create(:sidekiq_job, digest: digest, completed_at: Time.current) }
    let!(:job_4) { FactoryBot.create(:sidekiq_job, digest: "other", completed_at: Time.current) }
    let!(:job_5) { FactoryBot.create(:sidekiq_job, digest: "other_2", completed_at: nil) }
    let!(:job_6) { FactoryBot.create(:sidekiq_job, digest: digest, completed_at: nil) }

    it "marks all unprocessed jobs ith a given digest as processed excluding the one with provided ID" do
      expect {
        drop_unprocessed_jobs_by_digest
      }.to change { job_1.reload.dropped_at }.from(nil).to(current_time)
      .and change { job_1.dropped_by_job_id }.from(nil).to(1212)
      .and avoid_changing { job_2.reload.dropped_at }
      .and avoid_changing { job_2.dropped_by_job_id }
      .and avoid_changing { job_3.reload.dropped_at }
      .and avoid_changing { job_3.dropped_by_job_id }
      .and avoid_changing { job_4.reload.dropped_at }
      .and avoid_changing { job_4.dropped_by_job_id }
      .and avoid_changing { job_5.reload.dropped_at }
      .and avoid_changing { job_5.dropped_by_job_id }
      .and avoid_changing { job_6.reload.dropped_at }
      .and avoid_changing { job_6.dropped_by_job_id }
    end
  end
end
