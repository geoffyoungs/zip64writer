require 'test/unit'
require 'stringio'
$: << File.join(File.dirname(__FILE__), '../lib')
require 'zip64/writer'

class Zip64Test < Test::Unit::TestCase
	def test_small_std_zip
		io = StringIO.new
		
		Zip64::ZipWriter.new(io) { |zip| zip.add_entry(StringIO.new("Foo"), :name => 'bar.txt') }

		assert_equal 115, io.string.size
		assert_match /^PK/, io.string
		assert_match /bar.txtFoo/, io.string
	end
	def test_small_z64_zip
		io = StringIO.new
		
		Zip64::ZipWriter.new(io) { |zip| zip.add_entry(StringIO.new("Foo"), :name => 'bar.txt', :use => 64) }

		assert_equal 243, io.string.size
		assert_match /^PK/, io.string
		assert_match /bar.txt.*Foo/, io.string

		assert io.string.include?([Zip64::Zip64EOCDR::SIG].pack('V'))
	end
end

