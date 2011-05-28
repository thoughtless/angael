# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "angael/version"

Gem::Specification.new do |s|
  s.name        = "angael"
  s.version     = Angael::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Paul Cortens"]
  s.email       = ["paul@thoughtless.ca"]
  s.homepage    = "http://github.com/thoughtless/angael"
  s.summary     = %q{Lightweight library for running repetitive background processes.}
  #s.description = %q{TODO: Write a gem description}

  s.rubyforge_project = "angael"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_development_dependency('rspec', '2.6.0')
  s.add_development_dependency('rspec-process-mocks')
end
