ypt# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'noms/command/version'

Gem::Specification.new do |spec|
    spec.name          = "noms-command"
    spec.version       = NOMS::Command::VERSION
    spec.authors       = ["Jeremy Brinkley"]
    spec.email         = ["jbrinkley@evernote.com"]
    spec.summary       = %q{Interpreter for server-defined command-line interfaces}
    spec.homepage      = "http://github.com/en-jbrinkley/noms-command"
    spec.license       = "Apache-2"

    spec.files         = `git ls-files -z`.split("\x0")
    spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
    spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
    spec.require_paths = ["lib"]

    spec.add_runtime_dependency "therubyracer"
    spec.add_runtime_dependency "httpclient"
    spec.add_runtime_dependency "mime-types"
    spec.add_runtime_dependency "typhoeus"
    spec.add_runtime_dependency "json"
    spec.add_runtime_dependency "trollop"
    spec.add_runtime_dependency "highline"
    spec.add_runtime_dependency "bcrypt"

    spec.add_development_dependency "bundler", "~> 1.7"
    spec.add_development_dependency "rake", "~> 10.0"
    spec.add_development_dependency "rspec"
    spec.add_development_dependency "sinatra"
end
