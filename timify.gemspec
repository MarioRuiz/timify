# frozen_string_literal: true

require_relative "lib/timify/version"

Gem::Specification.new do |spec|
  spec.name = "timify"
  spec.version = Timify::VERSION
  spec.summary = "Calculate elapsed time from one location to another inside your code and report statistics."
  spec.description = "Calculate elapsed time from one location to another inside your code and report statistics. It helps you improve your code and find out which part of your code is consuming more time."
  spec.authors = ["Mario Ruiz"]
  spec.email = "marioruizs@gmail.com"
  spec.homepage = "https://github.com/MarioRuiz/timify"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*.rb", "LICENSE", "README.md", "CHANGELOG.md", ".yardopts"]
  end
  spec.extra_rdoc_files = ["LICENSE", "README.md", "CHANGELOG.md"]

  spec.metadata = {
    "changelog_uri" => "https://github.com/MarioRuiz/timify/blob/master/CHANGELOG.md",
    "source_code_uri" => "https://github.com/MarioRuiz/timify",
    "rubygems_mfa_required" => "true"
  }
end
