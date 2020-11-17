RSpec.describe SidekiqRobustJob::DigestGenerator do
  describe "#generate" do
    let(:generator) { described_class.new(backend: backend) }
    let(:backend) do
      Class.new do
        attr_reader :storage

        def initialize
          @storage = nil
        end

        def hexdigest(value)
          @storage = value
        end
      end.new
    end

    context "when extra arguments besides job_class are passed" do
      subject(:generate) { generator.generate(job_class, argument_1, argument_2) }

      let(:job_class) { Object }
      let(:argument_1) { double(:argument_1, to_s: "argument_1") }
      let(:argument_2) { double(:argument_2, to_s: "argument_2") }

      it "generates digest based on job class and arguments" do
        expect {
          generate
        }.to change { backend.storage }.from(nil).to("Object-argument_1-argument_2")
      end
    end

    context "when no extra arguments besides job_class are passed" do
      subject(:generate) { generator.generate(job_class) }

      let(:job_class) { Object }

      it "generates digest based on job class" do
        expect {
          generate
        }.to change { backend.storage }.from(nil).to("Object-")
      end
    end
  end
end
