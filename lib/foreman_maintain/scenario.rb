module ForemanMaintain
  class Scenario
    include Concerns::Logger
    include Concerns::SystemHelpers
    include Concerns::ScenarioMetadata
    include Concerns::Finders

    attr_reader :steps

    class FilteredScenario < Scenario
      metadata do
        manual_detection
        run_strategy :fail_slow
      end

      attr_reader :filter_label, :filter_tags

      def initialize(filter)
        @filter_tags = filter[:tags]
        @filter_label = filter[:label]
        @steps = ForemanMaintain.available_checks(filter).map(&:ensure_instance)
      end

      def description
        if @filter_label
          "check with label [#{dashize(@filter_label)}]"
        else
          "checks with tags #{tag_string(@filter_tags)}"
        end
      end

      private

      def tag_string(tags)
        tags.map { |tag| dashize("[#{tag}]") }.join(' ')
      end

      def dashize(string)
        string.to_s.tr('_', '-')
      end
    end

    class PreparationScenario < Scenario
      metadata do
        manual_detection
        description 'preparation steps required to run the next scenarios'
        run_strategy :fail_slow
      end

      attr_reader :main_scenario

      def initialize(main_scenario)
        @main_scenario = main_scenario
      end

      def steps
        @steps ||= main_scenario.preparation_steps.find_all(&:necessary?)
      end
    end

    def initialize
      @steps = []
      compose
    end

    # Override to compose steps for the scenario
    def compose; end

    def preparation_steps
      # we first take the preparation steps defined for the scenario + collect
      # preparation steps for the steps inside the scenario
      steps.inject(super.dup) do |results, step|
        results.concat(step.preparation_steps)
      end.uniq
    end

    def executed_steps
      steps.find_all(&:executed?)
    end

    def steps_with_error(options = {})
      filter_whitelisted(executed_steps.find_all(&:fail?), options)
    end

    def steps_with_warning(options = {})
      filter_whitelisted(executed_steps.find_all(&:warning?), options)
    end

    def filter_whitelisted(steps, options)
      options.validate_options!(:whitelisted)
      if options.key?(:whitelisted)
        steps.select do |step|
          options[:whitelisted] ? step.whitelisted? : !step.whitelisted?
        end
      else
        steps
      end
    end

    def passed?
      (steps_with_error(:whitelisted => false) + steps_with_warning(:whitelisted => false)).empty?
    end

    def failed?
      !passed?
    end

    # scenarios to be run before this scenario
    def before_scenarios
      scenarios = []
      preparation_scenario = PreparationScenario.new(self)
      scenarios << [preparation_scenario] unless preparation_scenario.steps.empty?
      scenarios
    end

    def add_steps(steps)
      steps.each do |step|
        self.steps << step.ensure_instance
      end
    end

    def add_step(step)
      add_steps([step])
    end

    def self.inspect
      "Scenario Class #{metadata[:description]}<#{name}>"
    end

    def inspect
      "#{self.class.metadata[:description]}<#{self.class.name}>"
    end
  end
end
