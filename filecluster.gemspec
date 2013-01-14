# -*- encoding: utf-8 -*-
require File.expand_path('../lib/fc/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["sh"]
  gem.email         = ["cntyrf@gmail.com"]
  gem.description   = %q{Distributed sorage}
  gem.summary       = %q{Distributed sorage}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "filecluster"
  gem.require_paths = ["lib"]
  gem.version       = FC::VERSION
  
  gem.add_development_dependency "rake"
  gem.add_development_dependency "mysql2"
  gem.add_development_dependency "shoulda"
  gem.add_development_dependency "mocha"
end
