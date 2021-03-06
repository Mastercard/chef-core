#
# Copyright:: Copyright (c) 2017 Chef Software Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require "train/errors"
require "pastel"
require "chef_core/error"
require "chef_core/text"
require "chef_core/cliux/ui/terminal"
require "chef_core/errors/standard_error_resolver"

module ChefCore
  module CLIUX
    module UI
      class ErrorPrinter
        attr_reader :id, :pastel, :translation, :exception, :target_host, :config

        # 't' is a convenience method for accessing error i18n error definitions.
        # It also serves as a workaround to let us verify that correct text key
        # lookups happen in unit tests.
        def t
          ChefCore::Text.errors
        end

        DEFAULT_ERROR_NO = "CHEFINT001".freeze

        def self.show_error(e, config)
          # Name is misleading - it's unwrapping but also doing further
          # error resolution for common errors:
          unwrapped = ChefCore::Errors::StandardErrorResolver.unwrap_exception(e)
          if unwrapped.class == ChefCore::MultiJobFailure
            capture_multiple_failures(unwrapped, config)
          end
          formatter = ErrorPrinter.new(wrapper: e,
                                       exception: unwrapped,
                                       config: config)

          Terminal.output(formatter.format_error)
        rescue => ex
          dump_unexpected_error(ex)
        end

        def self.capture_multiple_failures(e, config)
          e.params << config[:error_output_path] # Tell the operator where to find this info
          File.open(config[:error_output_path], "w") do |out|
            e.jobs.each do |j|
              wrapped = ChefCore::Errors::StandardErrorResolver.wrap_exception(j.exception, j.target_host)
              ep = ErrorPrinter.new(wrapper: wrapped, config: config)
              msg = ep.format_body.tr("\n", " ").gsub(/ {2,}/, " ").chomp.strip
              out.write("Host: #{j.target_host.hostname} ")
              if ep.exception.respond_to? :id
                out.write("Error: #{ep.exception.id}: ")
              else
                out.write(": ")
              end
              out.write("#{msg}\n")
            end
          end
        end

        def self.write_backtrace(e, args, config)
          formatter = ErrorPrinter.new(wrapper: e, config: config)
          out = StringIO.new
          formatter.add_backtrace_header(out, args)
          formatter.add_formatted_backtrace(out)
          formatter.save_backtrace(out, config)
        rescue => ex
          dump_unexpected_error(ex)
        end

        # Use this to dump an an exception to output. useful
        # if an error occurs in the error handling itself.
        def self.dump_unexpected_error(e)
          Terminal.output "INTERNAL ERROR"
          Terminal.output "-=" * 30
          Terminal.output "Message:"
          Terminal.output e.message if e.respond_to?(:message)
          Terminal.output "Backtrace:"
          Terminal.output e.backtrace if e.respond_to?(:backtrace)
          Terminal.output "=-" * 30
        end

        def initialize(wrapper: nil, config: nil, exception: nil)
          @exception = exception || wrapper.contained_exception
          @target_host = wrapper.target_host || target_host
          @command = @exception.respond_to?(:command) ? @exception.command : nil
          @pastel = Pastel.new
          @content = StringIO.new
          @config = config
          @id = if @exception.is_a? ChefCore::Error
                  @exception.id
                else
                  DEFAULT_ERROR_NO
                end
          @translation = ChefCore::Text::ErrorTranslation.new(id)
        rescue => e
          ErrorPrinter.dump_unexpected_error(e)
          exit! 128
        end

        def format_error
          if translation.decorations
            format_decorated
          else
            format_undecorated
          end
          @content.string
        end

        def format_undecorated
          @content << "\n"
          @content << format_body
          if @command
            @content << "\n"
            @content << @command.usage
          end
        end

        def format_decorated
          @content << "\n"
          @content << format_header
          @content << "\n\n"
          @content << format_body
          @content << "\n"
          @content << format_footer
          @content << "\n"
        end

        def format_header
          pastel.decorate(@id, :bold)
        end

        def format_body
          if exception.is_a? ChefCore::Error
            format_workstation_exception
          elsif exception.is_a? Train::Error
            format_train_exception
          else
            format_other_exception
          end
        end

        def format_footer
          if translation.log
            if translation.stack
              t.footer.both(config[:log_location], config[:stack_trace_path])
            else
              t.footer.log_only(config[:log_location])
            end
          else
            if translation.stack
              t.footer.stack_only
            else
              t.footer.neither
            end
          end
        end

        def add_backtrace_header(out, args)
          out.write("\n#{"-" * 80}\n")
          out.print("#{Time.now}: Error encountered while running the following:\n")
          out.print("  #{args.join(" ")}\n")
          out.print("Backtrace:\n")
        end

        def save_backtrace(output, config)
          File.open(config[:stack_trace_path], "ab+") do |f|
            f.write(output.string)
          end
        end

        def self.error_summary(e)
          if e.is_a? ChefCore::Error
            # By convention, all of our defined messages have a short summary on the first line.
            ChefCore::Text.errors.send(e.id).text(*e.params).split("\n").first
          elsif e.is_a? String
            e
          else
            if e.respond_to? :message
              e.message
            else
              ChefCore::Text.errors.UNKNOWN
            end
          end
        end

        def format_workstation_exception
          params = exception.params
          t.send(@id).text(*params)
        end

        # TODO this gets moved to trainerrormapper  or simply removed since
        #     many of these issues are now handled in the RemoteTarget::ConnectionFailure
        def format_train_exception
          backend, host = formatted_host
          if host.nil?
            t.CHEFTRN002.text(exception.message)
          else
            t.CHEFTRN001.text(backend, host, exception.message)
          end
        end

        def format_other_exception
          t.send(DEFAULT_ERROR_NO).text(exception.message)
        end

        def formatted_host
          return nil if target_host.nil?

          cfg = target_host.config
          port = cfg[:port].nil? ? "" : ":#{cfg[:port]}"
          user = cfg[:user].nil? ? "" : "#{cfg[:user]}@"
          "#{user}#{target_host.hostname}#{port}"
        end

        # mostly copied from
        # https://gist.github.com/stanio/13d74294ca1868fed7fb
        def add_formatted_backtrace(out)
          _format_single(out, exception)
          current_backtrace = exception.backtrace
          cause = exception.cause
          until cause.nil?
            cause_trace = _unique_trace(cause.backtrace.to_a, current_backtrace)
            out.print "Caused by: "
            _format_single(out, cause, cause_trace)
            backtrace_length = cause.backtrace.length
            if backtrace_length > cause_trace.length
              out.print "\t... #{backtrace_length - cause_trace.length} more"
            end
            out.print "\n"
            current_backtrace = cause.backtrace
            cause = cause.cause
          end
        end

        def _format_single(out, exception, backtrace = nil)
          out.puts "#{exception.class}: #{exception.message}"
          backtrace ||= exception.backtrace.to_a
          backtrace.each { |trace| out.puts "\t#{trace}" }
        end

        def _unique_trace(backtrace1, backtrace2)
          i = 1
          while i <= backtrace1.size && i <= backtrace2.size
            break if backtrace1[-i] != backtrace2[-i]

            i += 1
          end
          backtrace1[0..-i]
        end
      end

    end
  end
end
