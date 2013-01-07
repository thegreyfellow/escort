module Escort
  class App
    include Dsl
    include GlobalDsl

    class << self
      def create(options_string = nil, &block)
        self.new(options_string).tap do |app|
          block.call(app)  #run the block to get the various sub blocks
          begin
            app.use_default_options_string_if_needed
            app.parse_options # parse the global options
            if !app.command_names.nil? && app.command_names.size > 0
              app.current_command.parse_options # parse the current command options
              app.execute_before_block(app.current_command.name, app.current_options, app.current_command.current_options, app.arguments)
              app.current_command.perform_action(app.current_options, app.arguments)
            else
              app.perform_action(app.current_options, app.arguments)
            end
          rescue => e
            app.execute_error_block(e)
          end
        end
      end
    end

    attr_reader :current_options

    def initialize(options_string = nil)
      @options_string = options_string || ARGV.dup
    end

    def use_default_options_string_if_needed
      @default_options_string ||= ['-h']
      if @options_string.size == 0
        @options_string = @default_options_string
      end
    end

    def arguments
      @options_string
    end

    def parse_options
      parser = Trollop::Parser.new(&@options_block)
      parser.stop_on(@command_names)

      @current_options = Trollop::with_standard_exception_handling(parser) do
        parser.parse @options_string
      end
      validate_options(parser, @current_options)
    end

    def validate_options(parser, option_values)
      validation_options = Escort::ValidatioOptions.new
      #TODO make sure all keys match an option_values key
      @validations_block.call(validation_options)
      validation_options.validations.each_pair do |option, validation_data|
        raise "Unable to create validation for #{option} as no such option was defined, maybe you misspelled it" unless option_values.keys.include?(option)
        if option_values[option] && !validation_data[:validation].call(option_values[option])
          parser.die(option, validation_data[:message])
        end
      end
    end

    def current_command
      return @current_command if @current_command
      command_name = @options_string.shift.to_s
      command_block = @command_blocks[command_name]
      raise "No command was passed in" unless command_block
      @current_command = Command.new(command_name, @options_string)
      command_block.call(@current_command)
      @current_command
    end

    def execute_before_block(command_name, global_options, command_options, arguments)
      @before_block.call(command_name, global_options, command_options, arguments) if @before_block
    end

    def perform_action(current_options, arguments)
      if command_names.nil? || command_names.size == 0
        raise "Must define a global action block if there are no sub-commands" unless @action_block
        raise "Can't define before blocks if there are no sub-commands" if @before_block
        @action_block.call(current_options, arguments)
      else
        raise "Can't define global actions for an app with sub-commands"
      end
    end

    def execute_error_block(error)
      @error_block ? @error_block.call(error) : (raise error)
    end
  end
end
