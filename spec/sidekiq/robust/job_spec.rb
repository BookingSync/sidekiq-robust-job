RSpec.describe Sidekiq::Robust::Job do
  it "has a version number" do
    expect(Sidekiq::Robust::Job::VERSION).not_to be nil
  end
end
