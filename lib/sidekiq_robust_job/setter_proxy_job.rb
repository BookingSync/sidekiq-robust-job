class SidekiqRobustJob
  class SetterProxyJob
    def build(job_class, options)
      Class.new(SimpleDelegator) do
        attr_reader :job_class, :custom_options
        private     :job_class, :custom_options

        def initialize(job_class, custom_options = {})
          super(job_class)

          @job_class = job_class
          @custom_options = custom_options
        end

        # rubocop:disable Naming/AccessorMethodName
        def get_sidekiq_options
          job_class.get_sidekiq_options.merge(custom_options.stringify_keys)
        end
        # rubocop:enable Naming/AccessorMethodName

        def perform_async(*arguments)
          SidekiqRobustJob.perform_async(self, *arguments)
        end

        def perform_in(interval, *arguments)
          SidekiqRobustJob.perform_in(self, interval, *arguments)
        end

        def perform_at(time, *arguments)
          SidekiqRobustJob.perform_at(self, time, *arguments)
        end

        def set(options = {})
          SidekiqRobustJob.set(self, options)
        end

        def original_perform_in(*args)
          call_sidekiq_method(:perform_in, *args)
        end

        def original_perform_at(*args)
          call_sidekiq_method(:perform_at, *args)
        end

        def original_perform_async(*args)
          call_sidekiq_method(:perform_async, *args)
        end

        def original_set(*args)
          call_sidekiq_method(:set, *args)
        end

        # override to not fail on Sidekiq internal validation
        def is_a?(val)
          if val == Class
            true
          else
            super
          end
        end

        private

        def call_sidekiq_method(name, *args)
          Sidekiq::Worker::ClassMethods.instance_method(name).bind(self).call(*args)
        end
      end.new(job_class, options)
    end
  end
end
