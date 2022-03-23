RSpec.describe SidekiqRobustJob::SidekiqJobManager, :freeze_time do
  let(:manager) do
    described_class.new(
      jobs_repository: SidekiqRobustJob::DependenciesContainer["jobs_repository"],
      clock: clock,
      digest_generator: SidekiqRobustJob::DependenciesContainer["digest_generator"],
      memory_monitor: memory_monitor
    )
  end
  let(:clock) { double(now: current_time) }
  let(:current_time) { Time.current }
  let(:job_class) do
    Class.new do
      include Sidekiq::Worker
      include SidekiqRobustJob::SidekiqJobExtensions

      def self.to_s
        "TestJob"
      end
    end
  end
  let(:created_job) { SidekiqJob.order(:created_at).last }
  let(:memory_monitor) do
    Class.new do
      def initialize
        @called = false
      end

      def mb
        if @called
          100
        else
          50
          @called = true
        end
      end
    end.new
  end

  around do |example|
    original_clock = SidekiqRobustJob.configuration.clock
    original_memory_monitor = SidekiqRobustJob.configuration.memory_monitor
    original_sidekiq_job_model = SidekiqRobustJob.configuration.sidekiq_job_model

    SidekiqRobustJob.configure do |config|
      config.clock = Time.zone
      config.memory_monitor = memory_monitor
      config.sidekiq_job_model = SidekiqJob
    end

    example.run

    SidekiqRobustJob.configure do |config|
      config.clock = original_clock
      config.memory_monitor = original_memory_monitor
      config.sidekiq_job_model = original_sidekiq_job_model
    end
  end

  describe "#perform_async" do
    context "when job arguments are provided" do
      subject(:perform_async) { manager.perform_async(job_class, argument_1) }

      let(:argument_1) { "argument_1" }

      it "creates SidekiqJob" do
        expect {
          perform_async
        }.to change { SidekiqJob.count }.by(1)

        expect(created_job.attributes.except("id", "created_at", "updated_at")).to eq(
          "job_class" => job_class.to_s,
          "enqueued_at" => clock.now,
          "arguments" => ["argument_1"],
          "digest" => "48f2674d007cec267803ff199a733bca",
          "uniqueness_strategy" => "no_uniqueness",
          "completed_at" => nil,
          "dropped_at" => nil,
          "dropped_by_job_id" => nil,
          "enqueue_conflict_resolution_strategy" => "do_nothing",
          "failed_at" => nil,
          "started_at" => nil,
          "memory_usage_before_processing_in_megabytes" => nil,
          "memory_usage_after_processing_in_megabytes" => nil,
          "memory_usage_change_in_megabytes" => nil,
          "attempts" => 0,
          "error_type" => nil,
          "execute_at" => clock.now,
          "error_message" => nil,
          "queue" => "default",
          "sidekiq_jid" => job_class.jobs.last["jid"]
        )
      end

      it "enqueues job" do
        perform_async

        expect(job_class).to have_enqueued_sidekiq_job(created_job.id)
      end

      it "executes Do Nothing Enqueue Conflict Resolution Strategy by default" do
        expect_any_instance_of(SidekiqRobustJob::EnqueueConflictResolutionStrategy::DoNothing).to receive(:execute)
          .and_call_original

        perform_async
      end
    end

    context "when job arguments are not provided" do
      subject(:perform_async) { manager.perform_async(job_class) }

      it "creates SidekiqJob" do
        expect {
          perform_async
        }.to change { SidekiqJob.count }.by(1)

        expect(created_job.attributes.except("id", "created_at", "updated_at")).to eq(
          "job_class" => job_class.to_s,
          "enqueued_at" => clock.now,
          "arguments" => [],
          "digest" => "9f0b78b05e148842e0e51523cc8bbd2a",
          "uniqueness_strategy" => "no_uniqueness",
          "completed_at" => nil,
          "dropped_at" => nil,
          "dropped_by_job_id" => nil,
          "enqueue_conflict_resolution_strategy" => "do_nothing",
          "failed_at" => nil,
          "started_at" => nil,
          "memory_usage_before_processing_in_megabytes" => nil,
          "memory_usage_after_processing_in_megabytes" => nil,
          "memory_usage_change_in_megabytes" => nil,
          "attempts" => 0,
          "error_type" => nil,
          "execute_at" => clock.now,
          "error_message" => nil,
          "queue" => "default",
          "sidekiq_jid" => job_class.jobs.last["jid"]
        )
      end

      it "enqueues job" do
        perform_async

        expect(job_class).to have_enqueued_sidekiq_job(created_job.id)
      end

      it "executes Do Nothing Enqueue Conflict Resolution Strategy by default" do
        expect_any_instance_of(SidekiqRobustJob::EnqueueConflictResolutionStrategy::DoNothing).to receive(:execute)
          .and_call_original

        perform_async
      end
    end

    describe "when enqueuing with custom options" do
      subject(:perform_async) { manager.perform_async(job_class) }

      let(:job_class) do
        Class.new do
          include Sidekiq::Worker
          include SidekiqRobustJob::SidekiqJobExtensions

          sidekiq_options queue: "critical", uniqueness_strategy: "until_executed",
            enqueue_conflict_resolution_strategy: "drop_self", persist_self_dropped_jobs: false

          def self.to_s
            "TestJob"
          end
        end
      end

      it "creates job using these options" do
        expect {
          perform_async
        }.to change { SidekiqJob.count }.by(1)
        expect(created_job.queue).to eq "critical"
        expect(created_job.uniqueness_strategy).to eq "until_executed"
        expect(created_job.enqueue_conflict_resolution_strategy).to eq "drop_self"
      end

      it "executes specified Enqueue Conflict Resolution Strategy" do
        expect_any_instance_of(SidekiqRobustJob::EnqueueConflictResolutionStrategy::DropSelf).to receive(:execute)
          .and_call_original

        perform_async
      end
    end

    describe "when job is dropped by :drop_self enqueue conflict resolution strategy" do
      subject(:perform_async) { manager.perform_async(job_class) }

      let(:job_class) do
        Class.new do
          include Sidekiq::Worker
          include SidekiqRobustJob::SidekiqJobExtensions

          sidekiq_options enqueue_conflict_resolution_strategy: :drop_self

          def self.to_s
            "TestJob"
          end
        end
      end

      before do
        create(:sidekiq_job, digest: SidekiqRobustJob::DependenciesContainer["digest_generator"].generate(job_class))
      end

      it "does not push any job to sidekiq" do
        expect {
          perform_async
        }.not_to change { job_class.jobs.count }
      end

      context "when :persist_self_dropped_jobs is set to true" do
        let(:job_class) do
          Class.new do
            include Sidekiq::Worker
            include SidekiqRobustJob::SidekiqJobExtensions

            sidekiq_options enqueue_conflict_resolution_strategy: :drop_self, persist_self_dropped_jobs: true

            def self.to_s
              "TestJob"
            end
          end
        end

        it "persists the job, even after being dropped" do
          expect {
            perform_async
          }.to change { SidekiqJob.count }.by(1)
        end
      end

      context "when :persist_self_dropped_jobs is set to false" do
        let(:job_class) do
          Class.new do
            include Sidekiq::Worker
            include SidekiqRobustJob::SidekiqJobExtensions

            sidekiq_options enqueue_conflict_resolution_strategy: :drop_self, persist_self_dropped_jobs: false

            def self.to_s
              "TestJob"
            end
          end
        end

        it "does not persist the job" do
          expect {
            perform_async
          }.not_to change { SidekiqJob.count }
        end
      end

      context "when :persist_self_dropped_jobs is not set" do
        it "persists the job, even after being dropped" do
          expect {
            perform_async
          }.to change { SidekiqJob.count }.by(1)
        end
      end

      context "with race conditions happening" do
        let(:job_class) do
          Class.new do
            include Sidekiq::Worker
            include SidekiqRobustJob::SidekiqJobExtensions

            sidekiq_options enqueue_conflict_resolution_strategy: :drop_self, persist_self_dropped_jobs: false

            def self.to_s
              "TestJob"
            end
          end
        end

        # simulate parallel creation of identical job between uniq check and committing
        before do
          SidekiqJob.delete_all

          allow(manager).to receive(:resolve_potential_conflict_for_enqueueing).and_wrap_original do |method, *args|
            method.call(*args)
            create(:sidekiq_job, digest: SidekiqRobustJob::DependenciesContainer["digest_generator"].generate(job_class))
          end
        end

        it "unfortunatelt persists the job" do
          expect {
            perform_async
          }.to change { SidekiqJob.count }.from(0).to(2)
          expect(SidekiqJob.pluck(:digest).uniq.size).to eq 1
        end
      end
    end
  end

  describe "#perform_in" do
    let(:interval) { 5.seconds }

    context "when job arguments are provided" do
      subject(:perform_in) { manager.perform_in(job_class, interval, argument_1) }

      let(:argument_1) { "argument_1" }

      it "creates SidekiqJob" do
        expect {
          perform_in
        }.to change { SidekiqJob.count }.by(1)

        expect(created_job.attributes.except("id", "created_at", "updated_at")).to eq(
          "job_class" => job_class.to_s,
          "enqueued_at" => clock.now,
          "arguments" => ["argument_1"],
          "digest" => "48f2674d007cec267803ff199a733bca",
          "uniqueness_strategy" => "no_uniqueness",
          "completed_at" => nil,
          "dropped_at" => nil,
          "dropped_by_job_id" => nil,
          "enqueue_conflict_resolution_strategy" => "do_nothing",
          "failed_at" => nil,
          "started_at" => nil,
          "memory_usage_before_processing_in_megabytes" => nil,
          "memory_usage_after_processing_in_megabytes" => nil,
          "memory_usage_change_in_megabytes" => nil,
          "attempts" => 0,
          "error_type" => nil,
          "execute_at" => clock.now + interval,
          "error_message" => nil,
          "queue" => "default",
          "sidekiq_jid" => job_class.jobs.last["jid"]
       )
      end

      it "enqueues job" do
        perform_in

        expect(job_class).to have_enqueued_sidekiq_job(created_job.id).in(interval)
      end

      it "executes Do Nothing Enqueue Conflict Resolution Strategy by default" do
        expect_any_instance_of(SidekiqRobustJob::EnqueueConflictResolutionStrategy::DoNothing).to receive(:execute)
          .and_call_original

        perform_in
      end
    end

    context "when job arguments are not provided" do
      subject(:perform_in) { manager.perform_in(job_class, interval) }

      it "creates SidekiqJob" do
        expect {
          perform_in
        }.to change { SidekiqJob.count }.by(1)

        expect(created_job.attributes.except("id", "created_at", "updated_at")).to eq(
          "job_class" => job_class.to_s,
          "enqueued_at" => clock.now,
          "arguments" => [],
          "digest" => "9f0b78b05e148842e0e51523cc8bbd2a",
          "uniqueness_strategy" => "no_uniqueness",
          "completed_at" => nil,
          "dropped_at" => nil,
          "dropped_by_job_id" => nil,
          "enqueue_conflict_resolution_strategy" => "do_nothing",
          "failed_at" => nil,
          "started_at" => nil,
          "memory_usage_before_processing_in_megabytes" => nil,
          "memory_usage_after_processing_in_megabytes" => nil,
          "memory_usage_change_in_megabytes" => nil,
          "attempts" => 0,
          "error_type" => nil,
          "execute_at" => clock.now + interval,
          "error_message" => nil,
          "queue" => "default",
          "sidekiq_jid" => job_class.jobs.last["jid"]
       )
      end

      it "enqueues job" do
        perform_in

        expect(job_class).to have_enqueued_sidekiq_job(created_job.id).in(interval)
      end

      it "executes Do Nothing Enqueue Conflict Resolution Strategy by default" do
        expect_any_instance_of(SidekiqRobustJob::EnqueueConflictResolutionStrategy::DoNothing).to receive(:execute)
          .and_call_original

        perform_in
      end
    end

    describe "when enqueuing with custom options" do
      subject(:perform_in) { manager.perform_in(job_class, interval) }

      let(:job_class) do
        Class.new do
          include Sidekiq::Worker
          include SidekiqRobustJob::SidekiqJobExtensions

          sidekiq_options queue: "critical", uniqueness_strategy: "until_executed",
            enqueue_conflict_resolution_strategy: "drop_self", persist_self_dropped_jobs: false

          def self.to_s
            "TestJob"
          end
        end
      end

      it "creates job using these options" do
        expect {
          perform_in
        }.to change { SidekiqJob.count }.by(1)
        expect(created_job.queue).to eq "critical"
        expect(created_job.uniqueness_strategy).to eq "until_executed"
        expect(created_job.enqueue_conflict_resolution_strategy).to eq "drop_self"
      end

      it "executes specified Enqueue Conflict Resolution Strategy by default" do
        expect_any_instance_of(SidekiqRobustJob::EnqueueConflictResolutionStrategy::DropSelf).to receive(:execute)
          .and_call_original

        perform_in
      end
    end

    describe "when job is dropped by :drop_self enqueue conflict resolution strategy" do
      subject(:perform_in) { manager.perform_in(job_class, interval) }

      let(:job_class) do
        Class.new do
          include Sidekiq::Worker
          include SidekiqRobustJob::SidekiqJobExtensions

          sidekiq_options enqueue_conflict_resolution_strategy: :drop_self

          def self.to_s
            "TestJob"
          end
        end
      end

      before do
        create(:sidekiq_job, digest: SidekiqRobustJob::DependenciesContainer["digest_generator"].generate(job_class))
      end

      it "does not push any job to sidekiq" do
        expect {
          perform_in
        }.not_to change { job_class.jobs.count }
      end

      context "when :persist_self_dropped_jobs is set to true" do
        let(:job_class) do
          Class.new do
            include Sidekiq::Worker
            include SidekiqRobustJob::SidekiqJobExtensions

            sidekiq_options enqueue_conflict_resolution_strategy: :drop_self, persist_self_dropped_jobs: true

            def self.to_s
              "TestJob"
            end
          end
        end

        it "persists the job, even after being dropped" do
          expect {
            perform_in
          }.to change { SidekiqJob.count }.by(1)
        end
      end

      context "when :persist_self_dropped_jobs is set to false" do
        let(:job_class) do
          Class.new do
            include Sidekiq::Worker
            include SidekiqRobustJob::SidekiqJobExtensions

            sidekiq_options enqueue_conflict_resolution_strategy: :drop_self, persist_self_dropped_jobs: false

            def self.to_s
              "TestJob"
            end
          end
        end

        it "does not persist the job" do
          expect {
            perform_in
          }.not_to change { SidekiqJob.count }
        end
      end

      context "when :persist_self_dropped_jobs is not set" do
        it "persists the job, even after being dropped" do
          expect {
            perform_in
          }.to change { SidekiqJob.count }.by(1)
        end
      end
    end
  end

  describe "#perform_at" do
    let(:time) { Time.new(2030, 1, 1, 12, 0, 0) }

    context "when job arguments are provided" do
      subject(:perform_at) { manager.perform_at(job_class, time, argument_1) }

      let(:argument_1) { "argument_1" }

      it "creates SidekiqJob" do
        expect {
          perform_at
        }.to change { SidekiqJob.count }.by(1)

        expect(created_job.attributes.except("id", "created_at", "updated_at")).to eq(
          "job_class" => job_class.to_s,
          "enqueued_at" => clock.now,
          "arguments" => ["argument_1"],
          "digest" => "48f2674d007cec267803ff199a733bca",
          "uniqueness_strategy" => "no_uniqueness",
          "completed_at" => nil,
          "dropped_at" => nil,
          "dropped_by_job_id" => nil,
          "enqueue_conflict_resolution_strategy" => "do_nothing",
          "failed_at" => nil,
          "started_at" => nil,
          "memory_usage_before_processing_in_megabytes" => nil,
          "memory_usage_after_processing_in_megabytes" => nil,
          "memory_usage_change_in_megabytes" => nil,
          "attempts" => 0,
          "error_type" => nil,
          "execute_at" => time,
          "error_message" => nil,
          "queue" => "default",
          "sidekiq_jid" => job_class.jobs.last["jid"]
        )
      end

      it "enqueues job" do
        perform_at

        expect(job_class).to have_enqueued_sidekiq_job(created_job.id).at(time)
      end

      it "executes Do Nothing Enqueue Conflict Resolution Strategy by default" do
        expect_any_instance_of(SidekiqRobustJob::EnqueueConflictResolutionStrategy::DoNothing).to receive(:execute)
          .and_call_original

        perform_at
      end
    end

    context "when job arguments are not provided" do
      subject(:perform_at) { manager.perform_at(job_class, time) }

      it "creates SidekiqJob" do
        expect {
          perform_at
        }.to change { SidekiqJob.count }.by(1)

        expect(created_job.attributes.except("id", "created_at", "updated_at")).to eq(
          "job_class" => job_class.to_s,
          "enqueued_at" => clock.now,
          "arguments" => [],
          "digest" => "9f0b78b05e148842e0e51523cc8bbd2a",
          "uniqueness_strategy" => "no_uniqueness",
          "completed_at" => nil,
          "dropped_at" => nil,
          "dropped_by_job_id" => nil,
          "enqueue_conflict_resolution_strategy" => "do_nothing",
          "failed_at" => nil,
          "started_at" => nil,
          "memory_usage_before_processing_in_megabytes" => nil,
          "memory_usage_after_processing_in_megabytes" => nil,
          "memory_usage_change_in_megabytes" => nil,
          "attempts" => 0,
          "error_type" => nil,
          "execute_at" => time,
          "error_message" => nil,
          "queue" => "default",
          "sidekiq_jid" => job_class.jobs.last["jid"]
        )
      end

      it "enqueues job" do
        perform_at

        expect(job_class).to have_enqueued_sidekiq_job(created_job.id).at(time)
      end

      it "executes Do Nothing Enqueue Conflict Resolution Strategy by default" do
        expect_any_instance_of(SidekiqRobustJob::EnqueueConflictResolutionStrategy::DoNothing).to receive(:execute)
        .and_call_original

        perform_at
      end
    end

    describe "when enqueuing with custom options" do
      subject(:perform_at) { manager.perform_at(job_class, time) }

      let(:job_class) do
        Class.new do
          include Sidekiq::Worker
          include SidekiqRobustJob::SidekiqJobExtensions

          sidekiq_options queue: "critical", uniqueness_strategy: "until_executed",
            enqueue_conflict_resolution_strategy: "drop_self", persist_self_dropped_jobs: false

          def self.to_s
            "TestJob"
          end
        end
      end

      it "creates job using these options" do
        expect {
          perform_at
        }.to change { SidekiqJob.count }.by(1)
        expect(created_job.queue).to eq "critical"
        expect(created_job.uniqueness_strategy).to eq "until_executed"
        expect(created_job.enqueue_conflict_resolution_strategy).to eq "drop_self"
      end

      it "executes specified Enqueue Conflict Resolution Strategy by default" do
        expect_any_instance_of(SidekiqRobustJob::EnqueueConflictResolutionStrategy::DropSelf).to receive(:execute)
          .and_call_original

        perform_at
      end
    end

    describe "when job is dropped by :drop_self enqueue conflict resolution strategy" do
      subject(:perform_at) { manager.perform_at(job_class, time) }

      let(:job_class) do
        Class.new do
          include Sidekiq::Worker
          include SidekiqRobustJob::SidekiqJobExtensions

          sidekiq_options enqueue_conflict_resolution_strategy: :drop_self

          def self.to_s
            "TestJob"
          end
        end
      end

      before do
        create(:sidekiq_job, digest: SidekiqRobustJob::DependenciesContainer["digest_generator"].generate(job_class))
      end

      it "does not push any job to sidekiq" do
        expect {
          perform_at
        }.not_to change { job_class.jobs.count }
      end

      context "when :persist_self_dropped_jobs is set to true" do
        let(:job_class) do
          Class.new do
            include Sidekiq::Worker
            include SidekiqRobustJob::SidekiqJobExtensions

            sidekiq_options enqueue_conflict_resolution_strategy: :drop_self, persist_self_dropped_jobs: true

            def self.to_s
              "TestJob"
            end
          end
        end

        it "persists the job, even after being dropped" do
          expect {
            perform_at
          }.to change { SidekiqJob.count }.by(1)
        end
      end

      context "when :persist_self_dropped_jobs is set to false" do
        let(:job_class) do
          Class.new do
            include Sidekiq::Worker
            include SidekiqRobustJob::SidekiqJobExtensions

            sidekiq_options enqueue_conflict_resolution_strategy: :drop_self, persist_self_dropped_jobs: false

            def self.to_s
              "TestJob"
            end
          end
        end

        it "does not persist the job" do
          expect {
            perform_at
          }.not_to change { SidekiqJob.count }
        end
      end

      context "when :persist_self_dropped_jobs is not set" do
        it "persists the job, even after being dropped" do
          expect {
            perform_at
          }.to change { SidekiqJob.count }.by(1)
        end
      end
    end
  end

  describe "#perform" do
    subject(:perform) { manager.perform(job.id) }

    context "when job is unprocessable" do
      let(:job) { create(:sidekiq_job, dropped_at: Time.now) }

      it "returns early" do
        expect {
          perform
        }.not_to change { job.reload.started_at }
      end
    end

    context "when job is processable" do
      class SidekiqRobustJobSidekiqJobManagerTestJobSentinel
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
      class SidekiqRobustJobSidekiqJobManagerTestJob
        include Sidekiq::Worker
        include SidekiqRobustJob::SidekiqJobExtensions

        def call(argument)
          SidekiqRobustJobSidekiqJobManagerTestJobSentinel.call(argument)
        end
      end

      let(:argument) { "value" }
      let(:job) do
        create(:sidekiq_job, job_class: "SidekiqRobustJobSidekiqJobManagerTestJob", arguments: [argument])
      end

      around do |example|
        SidekiqRobustJobSidekiqJobManagerTestJobSentinel.reset

        example.run

        SidekiqRobustJobSidekiqJobManagerTestJobSentinel.reset
      end

      it "sets timestamp attributes, attempts and memory usage" do
        expect {
          perform
        }.to change { job.reload.started_at }
        .and change { job.completed_at }
        .and change { job.memory_usage_before_processing_in_megabytes }
        .and change { job.memory_usage_after_processing_in_megabytes }
        .and change { job.memory_usage_change_in_megabytes }
        .and change { job.attempts }
      end

      it "executes the actual Sidekiq job" do
        expect {
          perform
        }.to change { SidekiqRobustJobSidekiqJobManagerTestJobSentinel.called? }.from(false).to(true)
        .and change { SidekiqRobustJobSidekiqJobManagerTestJobSentinel.argument }.from(nil).to(argument)
      end
    end
  end

  describe "set" do
    describe "combining with perform_async" do
      context "when job arguments are provided" do
        subject(:perform_async) { manager.set(job_class, queue: "critical").perform_async(argument_1) }

        let(:argument_1) { "argument_1" }

        it "creates SidekiqJob respecting overrides from :set" do
          expect {
            perform_async
          }.to change { SidekiqJob.count }.by(1)

          expect(created_job.attributes.except("id", "created_at", "updated_at")).to eq(
            "job_class" => job_class.to_s,
            "enqueued_at" => clock.now,
            "arguments" => ["argument_1"],
            "digest" => "48f2674d007cec267803ff199a733bca",
            "uniqueness_strategy" => "no_uniqueness",
            "completed_at" => nil,
            "dropped_at" => nil,
            "dropped_by_job_id" => nil,
            "enqueue_conflict_resolution_strategy" => "do_nothing",
            "failed_at" => nil,
            "started_at" => nil,
            "memory_usage_before_processing_in_megabytes" => nil,
            "memory_usage_after_processing_in_megabytes" => nil,
            "memory_usage_change_in_megabytes" => nil,
            "attempts" => 0,
            "error_type" => nil,
            "execute_at" => clock.now,
            "error_message" => nil,
            "queue" => "critical",
            "sidekiq_jid" => job_class.jobs.last["jid"]
          )
        end

        it "enqueues job" do
          perform_async

          expect(job_class).to have_enqueued_sidekiq_job(created_job.id)
          expect(job_class.jobs.last["queue"]).to eq "critical"
        end

        it "executes Do Nothing Enqueue Conflict Resolution Strategy by default" do
          expect_any_instance_of(SidekiqRobustJob::EnqueueConflictResolutionStrategy::DoNothing).to receive(:execute)
            .and_call_original

          perform_async
        end
      end

      context "when job arguments are not provided" do
        subject(:perform_async) { manager.set(job_class, queue: "critical").perform_async }

        it "creates SidekiqJob respecting overrides from :set" do
          expect {
            perform_async
          }.to change { SidekiqJob.count }.by(1)

          expect(created_job.attributes.except("id", "created_at", "updated_at")).to eq(
            "job_class" => job_class.to_s,
            "enqueued_at" => clock.now,
            "arguments" => [],
            "digest" => "9f0b78b05e148842e0e51523cc8bbd2a",
            "uniqueness_strategy" => "no_uniqueness",
            "completed_at" => nil,
            "dropped_at" => nil,
            "dropped_by_job_id" => nil,
            "enqueue_conflict_resolution_strategy" => "do_nothing",
            "failed_at" => nil,
            "started_at" => nil,
            "memory_usage_before_processing_in_megabytes" => nil,
            "memory_usage_after_processing_in_megabytes" => nil,
            "memory_usage_change_in_megabytes" => nil,
            "attempts" => 0,
            "error_type" => nil,
            "execute_at" => clock.now,
            "error_message" => nil,
            "queue" => "critical",
            "sidekiq_jid" => job_class.jobs.last["jid"]
          )
        end

        it "enqueues job" do
          perform_async

          expect(job_class).to have_enqueued_sidekiq_job(created_job.id)
          expect(job_class.jobs.last["queue"]).to eq "critical"
        end

        it "executes Do Nothing Enqueue Conflict Resolution Strategy by default" do
          expect_any_instance_of(SidekiqRobustJob::EnqueueConflictResolutionStrategy::DoNothing).to receive(:execute)
            .and_call_original

          perform_async
        end
      end

      describe "when enqueuing with custom options" do
        subject(:perform_async) { manager.set(job_class, queue: "other").perform_async }

        let(:job_class) do
          Class.new do
            include Sidekiq::Worker
            include SidekiqRobustJob::SidekiqJobExtensions

            sidekiq_options queue: "critical", uniqueness_strategy: "until_executed",
              enqueue_conflict_resolution_strategy: "drop_self", persist_self_dropped_jobs: false

            def self.to_s
              "TestJob"
            end
          end
        end

        it "creates job using these options respecting overrides from :set" do
          expect {
            perform_async
          }.to change { SidekiqJob.count }.by(1)
          expect(created_job.queue).to eq "other"
          expect(created_job.uniqueness_strategy).to eq "until_executed"
          expect(created_job.enqueue_conflict_resolution_strategy).to eq "drop_self"
        end

        it "executes specified Enqueue Conflict Resolution Strategy" do
          expect_any_instance_of(SidekiqRobustJob::EnqueueConflictResolutionStrategy::DropSelf).to receive(:execute)
          .and_call_original

          perform_async
        end

        it "enqueues job" do
          perform_async

          expect(job_class).to have_enqueued_sidekiq_job(created_job.id)
          expect(job_class.jobs.last["queue"]).to eq "other"
        end
      end

      describe "when job is dropped by :drop_self enqueue conflict resolution strategy" do
        subject(:perform_async) { manager.set(job_class, queue: "critical").perform_async }

        let(:job_class) do
          Class.new do
            include Sidekiq::Worker
            include SidekiqRobustJob::SidekiqJobExtensions

            sidekiq_options enqueue_conflict_resolution_strategy: :drop_self

            def self.to_s
              "TestJob"
            end
          end
        end

        before do
          create(:sidekiq_job, digest: SidekiqRobustJob::DependenciesContainer["digest_generator"].generate(job_class))
        end

        it "does not push any job to sidekiq" do
          expect {
            perform_async
          }.not_to change { job_class.jobs.count }
        end

        context "when :persist_self_dropped_jobs is set to true" do
          let(:job_class) do
            Class.new do
              include Sidekiq::Worker
              include SidekiqRobustJob::SidekiqJobExtensions

              sidekiq_options enqueue_conflict_resolution_strategy: :drop_self, persist_self_dropped_jobs: true

              def self.to_s
                "TestJob"
              end
            end
          end

          it "persists the job, even after being dropped" do
            expect {
              perform_async
            }.to change { SidekiqJob.count }.by(1)
          end
        end

        context "when :persist_self_dropped_jobs is set to false" do
          let(:job_class) do
            Class.new do
              include Sidekiq::Worker
              include SidekiqRobustJob::SidekiqJobExtensions

              sidekiq_options enqueue_conflict_resolution_strategy: :drop_self, persist_self_dropped_jobs: false

              def self.to_s
                "TestJob"
              end
            end
          end

          it "does not persist the job" do
            expect {
              perform_async
            }.not_to change { SidekiqJob.count }
          end
        end

        context "when :persist_self_dropped_jobs is not set" do
          it "persists the job, even after being dropped" do
            expect {
              perform_async
            }.to change { SidekiqJob.count }.by(1)
          end
        end
      end
    end

    describe "combining with perform_in" do
      let(:interval) { 5.seconds }

      context "when job arguments are provided" do
        subject(:perform_in) { manager.set(job_class, queue: "critical").perform_in(interval, argument_1) }

        let(:argument_1) { "argument_1" }

        it "creates SidekiqJob respecting overrides from :set" do
          expect {
            perform_in
          }.to change { SidekiqJob.count }.by(1)

          expect(created_job.attributes.except("id", "created_at", "updated_at")).to eq(
            "job_class" => job_class.to_s,
            "enqueued_at" => clock.now,
            "arguments" => ["argument_1"],
            "digest" => "48f2674d007cec267803ff199a733bca",
            "uniqueness_strategy" => "no_uniqueness",
            "completed_at" => nil,
            "dropped_at" => nil,
            "dropped_by_job_id" => nil,
            "enqueue_conflict_resolution_strategy" => "do_nothing",
            "failed_at" => nil,
            "started_at" => nil,
            "memory_usage_before_processing_in_megabytes" => nil,
            "memory_usage_after_processing_in_megabytes" => nil,
            "memory_usage_change_in_megabytes" => nil,
            "attempts" => 0,
            "error_type" => nil,
            "execute_at" => clock.now + interval,
            "error_message" => nil,
            "queue" => "critical",
            "sidekiq_jid" => job_class.jobs.last["jid"]
          )
        end

        it "enqueues job" do
          perform_in

          expect(job_class).to have_enqueued_sidekiq_job(created_job.id).in(interval)
          expect(job_class.jobs.last["queue"]).to eq "critical"
        end

        it "executes Do Nothing Enqueue Conflict Resolution Strategy by default" do
          expect_any_instance_of(SidekiqRobustJob::EnqueueConflictResolutionStrategy::DoNothing).to receive(:execute)
            .and_call_original

          perform_in
        end
      end

      context "when job arguments are not provided" do
        subject(:perform_in) { manager.set(job_class, queue: "critical").perform_in(interval) }

        it "creates SidekiqJob respecting overrides from :set" do
          expect {
            perform_in
          }.to change { SidekiqJob.count }.by(1)

          expect(created_job.attributes.except("id", "created_at", "updated_at")).to eq(
            "job_class" => job_class.to_s,
            "enqueued_at" => clock.now,
            "arguments" => [],
            "digest" => "9f0b78b05e148842e0e51523cc8bbd2a",
            "uniqueness_strategy" => "no_uniqueness",
            "completed_at" => nil,
            "dropped_at" => nil,
            "dropped_by_job_id" => nil,
            "enqueue_conflict_resolution_strategy" => "do_nothing",
            "failed_at" => nil,
            "started_at" => nil,
            "memory_usage_before_processing_in_megabytes" => nil,
            "memory_usage_after_processing_in_megabytes" => nil,
            "memory_usage_change_in_megabytes" => nil,
            "attempts" => 0,
            "error_type" => nil,
            "execute_at" => clock.now + interval,
            "error_message" => nil,
            "queue" => "critical",
            "sidekiq_jid" => job_class.jobs.last["jid"]
          )
        end

        it "enqueues job" do
          perform_in

          expect(job_class).to have_enqueued_sidekiq_job(created_job.id).in(interval)
          expect(job_class.jobs.last["queue"]).to eq "critical"
        end

        it "executes Do Nothing Enqueue Conflict Resolution Strategy by default" do
          expect_any_instance_of(SidekiqRobustJob::EnqueueConflictResolutionStrategy::DoNothing).to receive(:execute)
            .and_call_original

          perform_in
        end
      end

      describe "when enqueuing with custom options" do
        subject(:perform_in) { manager.set(job_class, queue: "other").perform_in(interval) }

        let(:job_class) do
          Class.new do
            include Sidekiq::Worker
            include SidekiqRobustJob::SidekiqJobExtensions

            sidekiq_options queue: "critical", uniqueness_strategy: "until_executed",
              enqueue_conflict_resolution_strategy: "drop_self", persist_self_dropped_jobs: false

            def self.to_s
              "TestJob"
            end
          end
        end

        it "creates job using these options" do
          expect {
            perform_in
          }.to change { SidekiqJob.count }.by(1)
          expect(created_job.queue).to eq "other"
          expect(created_job.uniqueness_strategy).to eq "until_executed"
          expect(created_job.enqueue_conflict_resolution_strategy).to eq "drop_self"
        end

        it "executes specified Enqueue Conflict Resolution Strategy by default" do
          expect_any_instance_of(SidekiqRobustJob::EnqueueConflictResolutionStrategy::DropSelf).to receive(:execute)
            .and_call_original

          perform_in
        end

        it "enqueues job" do
          perform_in

          expect(job_class).to have_enqueued_sidekiq_job(created_job.id).in(interval)
          expect(job_class.jobs.last["queue"]).to eq "other"
        end
      end

      describe "when job is dropped by :drop_self enqueue conflict resolution strategy" do
        subject(:perform_in) { manager.set(job_class, queue: "critical").perform_in(interval) }

        let(:job_class) do
          Class.new do
            include Sidekiq::Worker
            include SidekiqRobustJob::SidekiqJobExtensions

            sidekiq_options enqueue_conflict_resolution_strategy: :drop_self

            def self.to_s
              "TestJob"
            end
          end
        end

        before do
          create(:sidekiq_job, digest: SidekiqRobustJob::DependenciesContainer["digest_generator"].generate(job_class))
        end

        it "does not push any job to sidekiq" do
          expect {
            perform_in
          }.not_to change { job_class.jobs.count }
        end

        context "when :persist_self_dropped_jobs is set to true" do
          let(:job_class) do
            Class.new do
              include Sidekiq::Worker
              include SidekiqRobustJob::SidekiqJobExtensions

              sidekiq_options enqueue_conflict_resolution_strategy: :drop_self, persist_self_dropped_jobs: true

              def self.to_s
                "TestJob"
              end
            end
          end

          it "persists the job, even after being dropped" do
            expect {
              perform_in
            }.to change { SidekiqJob.count }.by(1)
          end
        end

        context "when :persist_self_dropped_jobs is set to false" do
          let(:job_class) do
            Class.new do
              include Sidekiq::Worker
              include SidekiqRobustJob::SidekiqJobExtensions

              sidekiq_options enqueue_conflict_resolution_strategy: :drop_self, persist_self_dropped_jobs: false

              def self.to_s
                "TestJob"
              end
            end
          end

          it "does not persist the job" do
            expect {
              perform_in
            }.not_to change { SidekiqJob.count }
          end
        end

        context "when :persist_self_dropped_jobs is not set" do
          it "persists the job, even after being dropped" do
            expect {
              perform_in
            }.to change { SidekiqJob.count }.by(1)
          end
        end
      end
    end

    describe "combining with perform_at" do
      let(:time) { Time.new(2030, 1, 1, 12, 0, 0) }

      context "when job arguments are provided" do
        subject(:perform_at) { manager.set(job_class, queue: "critical").perform_at(time, argument_1) }

        let(:argument_1) { "argument_1" }

        it "creates SidekiqJob respecting overrides from :set" do
          expect {
            perform_at
          }.to change { SidekiqJob.count }.by(1)

          expect(created_job.attributes.except("id", "created_at", "updated_at")).to eq(
            "job_class" => job_class.to_s,
            "enqueued_at" => clock.now,
            "arguments" => ["argument_1"],
            "digest" => "48f2674d007cec267803ff199a733bca",
            "uniqueness_strategy" => "no_uniqueness",
            "completed_at" => nil,
            "dropped_at" => nil,
            "dropped_by_job_id" => nil,
            "enqueue_conflict_resolution_strategy" => "do_nothing",
            "failed_at" => nil,
            "started_at" => nil,
            "memory_usage_before_processing_in_megabytes" => nil,
            "memory_usage_after_processing_in_megabytes" => nil,
            "memory_usage_change_in_megabytes" => nil,
            "attempts" => 0,
            "error_type" => nil,
            "execute_at" => time,
            "error_message" => nil,
            "queue" => "critical",
            "sidekiq_jid" => job_class.jobs.last["jid"]
          )
        end

        it "enqueues job" do
          perform_at

          expect(job_class).to have_enqueued_sidekiq_job(created_job.id).at(time)
          expect(job_class.jobs.last["queue"]).to eq "critical"
        end

        it "executes Do Nothing Enqueue Conflict Resolution Strategy by default" do
          expect_any_instance_of(SidekiqRobustJob::EnqueueConflictResolutionStrategy::DoNothing).to receive(:execute)
            .and_call_original

          perform_at
        end
      end

      context "when job arguments are not provided" do
        subject(:perform_at) { manager.set(job_class, queue: "critical").perform_at(time) }

        it "creates SidekiqJob respecting overrides from :set" do
          expect {
            perform_at
          }.to change { SidekiqJob.count }.by(1)

          expect(created_job.attributes.except("id", "created_at", "updated_at")).to eq(
            "job_class" => job_class.to_s,
            "enqueued_at" => clock.now,
            "arguments" => [],
            "digest" => "9f0b78b05e148842e0e51523cc8bbd2a",
            "uniqueness_strategy" => "no_uniqueness",
            "completed_at" => nil,
            "dropped_at" => nil,
            "dropped_by_job_id" => nil,
            "enqueue_conflict_resolution_strategy" => "do_nothing",
            "failed_at" => nil,
            "started_at" => nil,
            "memory_usage_before_processing_in_megabytes" => nil,
            "memory_usage_after_processing_in_megabytes" => nil,
            "memory_usage_change_in_megabytes" => nil,
            "attempts" => 0,
            "error_type" => nil,
            "execute_at" => time,
            "error_message" => nil,
            "queue" => "critical",
            "sidekiq_jid" => job_class.jobs.last["jid"]
          )
        end

        it "enqueues job" do
          perform_at

          expect(job_class).to have_enqueued_sidekiq_job(created_job.id).at(time)
          expect(job_class.jobs.last["queue"]).to eq "critical"
        end

        it "executes Do Nothing Enqueue Conflict Resolution Strategy by default" do
          expect_any_instance_of(SidekiqRobustJob::EnqueueConflictResolutionStrategy::DoNothing).to receive(:execute)
            .and_call_original

          perform_at
        end
      end

      describe "when enqueuing with custom options" do
        subject(:perform_at) { manager.set(job_class, queue: "other").perform_at(time) }

        let(:job_class) do
          Class.new do
            include Sidekiq::Worker
            include SidekiqRobustJob::SidekiqJobExtensions

            sidekiq_options queue: "critical", uniqueness_strategy: "until_executed",
              enqueue_conflict_resolution_strategy: "drop_self", persist_self_dropped_jobs: false

            def self.to_s
              "TestJob"
            end
          end
        end

        it "creates job using these options" do
          expect {
            perform_at
          }.to change { SidekiqJob.count }.by(1)
          expect(created_job.queue).to eq "other"
          expect(created_job.uniqueness_strategy).to eq "until_executed"
          expect(created_job.enqueue_conflict_resolution_strategy).to eq "drop_self"
        end

        it "executes specified Enqueue Conflict Resolution Strategy by default" do
          expect_any_instance_of(SidekiqRobustJob::EnqueueConflictResolutionStrategy::DropSelf).to receive(:execute)
            .and_call_original

          perform_at
        end

        it "enqueues job" do
          perform_at

          expect(job_class).to have_enqueued_sidekiq_job(created_job.id).at(time)
          expect(job_class.jobs.last["queue"]).to eq "other"
        end
      end

      describe "when job is dropped by :drop_self enqueue conflict resolution strategy" do
        subject(:perform_at) { manager.set(job_class, queue: "critical").perform_at(time) }

        let(:job_class) do
          Class.new do
            include Sidekiq::Worker
            include SidekiqRobustJob::SidekiqJobExtensions

            sidekiq_options enqueue_conflict_resolution_strategy: :drop_self

            def self.to_s
              "TestJob"
            end
          end
        end

        before do
          create(:sidekiq_job, digest: SidekiqRobustJob::DependenciesContainer["digest_generator"].generate(job_class))
        end

        it "does not push any job to sidekiq" do
          expect {
            perform_at
          }.not_to change { job_class.jobs.count }
        end

        context "when :persist_self_dropped_jobs is set to true" do
          let(:job_class) do
            Class.new do
              include Sidekiq::Worker
              include SidekiqRobustJob::SidekiqJobExtensions

              sidekiq_options enqueue_conflict_resolution_strategy: :drop_self, persist_self_dropped_jobs: true

              def self.to_s
                "TestJob"
              end
            end
          end

          it "persists the job, even after being dropped" do
            expect {
              perform_at
            }.to change { SidekiqJob.count }.by(1)
          end
        end

        context "when :persist_self_dropped_jobs is set to false" do
          let(:job_class) do
            Class.new do
              include Sidekiq::Worker
              include SidekiqRobustJob::SidekiqJobExtensions

              sidekiq_options enqueue_conflict_resolution_strategy: :drop_self, persist_self_dropped_jobs: false

              def self.to_s
                "TestJob"
              end
            end
          end

          it "does not persist the job" do
            expect {
              perform_at
            }.not_to change { SidekiqJob.count }
          end
        end

        context "when :persist_self_dropped_jobs is not set" do
          it "persists the job, even after being dropped" do
            expect {
              perform_at
            }.to change { SidekiqJob.count }.by(1)
          end
        end
      end
    end
  end
end
