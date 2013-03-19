# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'kodama/version'

Gem::Specification.new do |gem|
  gem.name          = "kodama"
  gem.version       = Kodama::VERSION
  gem.authors       = ["Yusuke Mito"]
  gem.email         = ["y310.1984@gmail.com"]
  gem.description   = %q{ruby-binlog based MySQL replication listener}
  gem.summary       = %q{ruby-binlog based MySQL replication listener}
  gem.homepage      = "https://github.com/y310/kodama"

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_dependency 'ruby-binlog', '>= 0.1.9'

  gem.add_development_dependency 'rake'
  gem.add_development_dependency 'rspec'
  gem.add_development_dependency 'pry'
  gem.add_development_dependency 'pry-nav'
  gem.add_development_dependency 'guard-rspec', '2.1.2'
  gem.add_development_dependency 'rb-fsevent', '~> 0.9.1'
end
