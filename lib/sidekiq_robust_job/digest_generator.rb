class SidekiqRobustJob
  class DigestGenerator
    attr_reader :backend
    private     :backend

    def initialize(backend:)
      @backend = backend
    end

    def generate(job_class, *arguments)
      backend.hexdigest("#{job_class}-#{Array(arguments).join('-')}")
    end
  end
end
