#
# Copyright:: Copyright (c) 2018 Chef Software Inc.
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

require "bundler/setup"
require "rspec/expectations"
require "support/matchers/output_to_terminal"
require "rbconfig"

require "simplecov"
if ENV["CIRCLE_ARTIFACTS"]
  dir = File.join(ENV["CIRCLE_ARTIFACTS"], "coverage")
  SimpleCov.coverage_dir(dir)
end
SimpleCov.start

require "simplecov"
require "chef_core"
require "chef_core/text"

RemoteExecResult = Struct.new(:exit_status, :stdout, :stderr)

module ChefCore
  module Testing
    class MockReporter
      def update(msg); ChefCore::CLIUX::UI::Terminal.output msg; end

      def success(msg); ChefCore::CLIUX::UI::Terminal.output "SUCCESS: #{msg}"; end

      def error(msg); ChefCore::CLIUX::UI::Terminal.output "FAILURE: #{msg}"; end
    end
  end
end
# TODO would read better to make this a custom matcher.
# Simulates a recursive string lookup on the Text object
#
# assert_string_lookup("tree.tree.tree.leaf", "a returned string")
# TODO this can be more cleanly expressed as a custom matcher...
def assert_string_lookup(key, retval = "testvalue")
  it "should look up string #{key}" do
    top_level_method, *call_seq = key.split(".")
    terminal_method = call_seq.pop
    tmock = double
    # Because ordering is important
    # (eg calling errors.hello is different from hello.errors),
    # we need to add this individually instead of using
    # `receive_messages`, which doesn't appear to give a way to
    # guarantee ordering
    expect(ChefCore::Text).to receive(top_level_method)
      .and_return(tmock)
    call_seq.each do |m|
      expect(tmock).to receive(m).ordered.and_return(tmock)
    end
    expect(tmock).to receive(terminal_method)
      .ordered.and_return(retval)
    subject.call
  end
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"
  config.run_all_when_everything_filtered = true
  config.filter_run :focus

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.before(:all) do
    windows  = RbConfig::CONFIG["host_os"] =~ /mswin|mingw/
    null_dev = windows ? "NUL" : "/dev/null"

    ChefCore::Log.setup null_dev, :error
  end
end

if ENV["CIRCLE_ARTIFACTS"]
  dir = File.join(ENV["CIRCLE_ARTIFACTS"], "coverage")
  SimpleCov.coverage_dir(dir)
end
SimpleCov.start
