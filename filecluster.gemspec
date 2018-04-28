# -*- encoding: utf-8 -*-
require File.expand_path('../lib/fc/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["sh"]
  gem.email         = ["cntyrf@gmail.com"]
  gem.description   = %q{Distributed storage}
  gem.summary       = %q{Distributed storage}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "filecluster"
  gem.require_paths = ["lib"]
  gem.version       = FC::VERSION
  
  gem.add_runtime_dependency "mysql2"
  
  gem.add_development_dependency "bundler"
  gem.add_development_dependency "test-unit"
  gem.add_development_dependency "rake"
  gem.add_development_dependency "shoulda-context"
  gem.add_development_dependency "mocha", ">= 0.13.3"
  gem.add_development_dependency "byebug"
end
