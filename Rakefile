require 'rake/testtask'

Rake::TestTask.new do |t|
  t.test_files = FileList['test/*_test.rb']
  t.verbose = true
end

require 'rubygems/package_task'

$: << 'lib'

require 'zip64/version'

spec = Gem::Specification.new do |s|
  s.platform = Gem::Platform::RUBY
  s.summary = "Zip64 Output Library"
  s.authors = ["Geoff Youngs"]
  s.email   = 'git@intersect-uk.co.uk'
  s.homepage = 'http://github.com/geoffyoungs/zip64writer'
  s.name = 'zip64writer'
  s.version = Zip64::VERSION.to_s
  s.requirements << 'none'
  s.require_path = 'lib'
  s.files = FileList['lib/zip64/*.rb']
  s.test_files = FileList['test/*_test.rb'] + ['Rakefile']
  s.description = <<EOF
A simple library to output Zip64 zip files from pure ruby.
EOF
end

Gem::PackageTask.new(spec) do |pkg|
  pkg.need_zip = true
  pkg.need_tar = true
end

