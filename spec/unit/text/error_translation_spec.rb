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

require "spec_helper"
require "chef_core/text"

RSpec.describe ChefCore::Text::ErrorTranslation do
  let(:display_defaults) do
    # This is a string of yaml that gets parsed at run time in ErrorTranslation
    "{
        decorations: true,
        header: true,
        footer: true,
        stack: false,
        log: false
     }"
  end

  let(:test_error_text) { "This is a test error" }
  # Individual contexts set these:
  let(:test_error) { {} }
  let(:test_display_opts) { nil }

  subject { ChefCore::Text::ErrorTranslation }
  let(:error_mock) do
    double("R18n::Translated", text: test_error_text )
  end

  # R18n translation mock
  let(:errors_translation_mock) do
    double("R18n::Translated",
      display_defaults: display_defaults,
      TESTERROR: error_mock)
  end
  before do
    # Mock out the R18n portion - our methods care only that the key exists; these
    # tests focus on proper loading of display metadata from correct R18n object its
    # Text wrapper.
    allow(ChefCore::Text).to receive(:errors).and_return errors_translation_mock
    unless test_display_opts.nil?
      allow(error_mock).to receive(:options).and_return test_display_opts
    end
  end

  context "when some display attributes are specified" do
    let(:test_display_opts) { "{ stack: true, log: true }" }
    it "sets display attributes to specified values and defaults remaining" do
      translation = subject.new("TESTERROR")
      expect(translation.decorations).to be true
      expect(translation.header).to be true
      expect(translation.footer).to be true
      expect(translation.stack).to be true
      expect(translation.log).to be true
      expect(translation.message).to eq test_error_text
    end
  end

  context "when all display attributes are specified" do
    let(:test_display_opts) { "{decorations: false, header: false, footer: false, stack: true, log: true }" }
    it "sets display attributes to specified values with no defaults" do
      translation = subject.new("TESTERROR")
      expect(translation.header).to be false
      expect(translation.decorations).to be false
      expect(translation.footer).to be false
      expect(translation.stack).to be true
      expect(translation.log).to be true
      expect(translation.message).to eq test_error_text
    end
  end

  context "when no attributes for an error are specified" do
    let(:test_display_opts) { nil }
    it "sets display attribute to default values and references the correct message" do
      translation = subject.new("TESTERROR")
      expect(translation.decorations).to be true
      expect(translation.header).to be true
      expect(translation.footer).to be true
      expect(translation.stack).to be false
      expect(translation.log).to be false
      expect(translation.message).to eq test_error_text
    end
  end

  context "when invalid attributes for an error are specified" do
    let(:test_display_opts) { "{ bad_value: true }" }
    it "raises InvalidDisplayAttributes when invalid attributes are specified" do
      expect { subject.new("TESTERROR") }
        .to raise_error(ChefCore::Text::ErrorTranslation::InvalidDisplayAttributes) do |e|
          expect(e.invalid_attrs).to eq({ bad_value: true })
        end

    end
  end
end
