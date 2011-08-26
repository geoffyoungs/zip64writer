require 'zlib'
require 'zip64/structures'
require 'stringio'

module Zip64
module_function
def time_to_msdos_time(time)
	mt = 0

	mt |= time.sec
	mt |= time.min << 5
	mt |= time.hour << 11

	mt
end
def date_to_msdos_date(date)
	md = 0

	md |= date.day
	md |= date.month << 5
	md |= (date.year - 1980) << 9

	md
end

class ZipWriter
	def initialize(io)
		@io, @offset = io, 0
		@dir_entries = []
		if block_given?
			yield(self)
			close
		end
	end

	def add_entry(io, info)
		mtime = Time.now
		mtime = info[:mtime]

		filename = info[:name]
		filename ||= File.basename(io.path) if io.respond_to?(:path) && io.path
		filename ||= "file-#{@dir_entries.size+2}.dat"

		data = io.read

		crc = Zlib.crc32(data,0)

		header = LocalFileHeader.new(
			:flags => 0,
			:last_mod_file_time => Zip64.time_to_msdos_time(mtime),
			:last_mod_file_date => Zip64.date_to_msdos_date(mtime),
			:crc32 => crc,
			:data_len => LEN64,
			:raw_data_len => LEN64,
			:filename => filename)

		header.extra_field = Zip64ExtraField.new(
			:header_id => Zip64ExtraField::ID,
			:header_len => 16,
			:raw_data_len => data.size,
			:data_len => data.size).to_string

		@dir_entries << {
			:local_header => header,
			:offset => @offset,
			:len => data.size
		}
		# write output
		write header.to_string

		# write data (& any compression?)
		write data
		# write descriptor

		#write DD64.new(:crc32 => crc,
		#			:data_len => data.size,
		#			:raw_data_len => data.size).to_string
	end

	def close
		#[archive decryption header]
		#[archive extra data record] 
		#[central directory]
		align
		cd_offset = @offset
		
		@dir_entries.each do |entry|
			offset = entry[:offset]
			len    = entry[:len]
			header = entry[:local_header]

			extra_field = Zip64CDExtraField.new(
				:data_len => len,
				:raw_data_len => len,
				:relative_offset => offset,
				:disk_no => 0
			)
			write CDFileHeader.new(
				:made_by => 3,
				:last_mod_file_time => header.last_mod_file_time,
				:last_mod_file_date => header.last_mod_file_date,
				:crc32 => header.crc32,				
				:data_len => LEN64,
				:raw_data_len => LEN64,
				:filename => header.filename,
				:extra_field => extra_field.to_string,
				:file_comment => '',
				:disk_no => 0xffff,
				:internal_file_attributes => 0,
				:external_file_attributes => 0,
				:rel_offset_of_local_header => LEN64
			).to_string
		end

		#write DigSig.new(
		#	:data => ''
		#).to_string

		cd_size = @offset - cd_offset #	Central Directory Size

		#[zip64 end of central directory record]
		z64_cd_offset = @offset
		
		write Zip64EOCDR.new(
		#	:record_len => ?,  # auto-filled in
			:made_by => 45,
			:this_disk_no => 0,
			:disk_with_cd_no => 0,
			:total_no_entries_on_this_disk => @dir_entries.size,
			:total_no_entries => @dir_entries.size,
			:size_of_cd => cd_size,
			:offset_of_cd_wrt_disk_no => cd_offset,
			:data => ''
		).to_string

		#[zip64 end of central directory locator]
		write Zip64EOCDL.new(
			:disk_with_z64_eocdr => 0,
			# Assume relative offset is relative to disk, as 
			# is case elsewhere in Zip spec
			:relative_offset => z64_cd_offset,
			:no_disks => 1
		).to_string

		#[end of central directory record]
		write EOCDR.new(
			:disk_no => 0,
			:disk_with_cd_no => 0,
			:total_entries_in_local_cd => @dir_entries.size,
			:total_entries => @dir_entries.size,
			:cd_size => cd_size,
			:offset_to_cd_start => cd_offset,
			:file_comment => ''
		).to_string
	end

	protected
	def align
		until (@offset % 4).zero?
			@io << "\0"
			@offset += 1
		end
	end
	def write(bytes)
		bytes = bytes.to_string unless bytes.is_a?(String)
		write_raw(bytes)
	end
	def write_raw(bytes)
		@io << bytes
		@offset += bytes.size
	end

	class FakeIO
		def initialize(buf)
			@io = StringIO.new(buf)
		end
		def read
			@io.read
		end
	end
	def self.test
		File.open("test.zip", "w") do |fp|
			ZipWriter.new(fp) do |writer|
				15.times do |x|
				writer.add_entry(StringIO.new("Foo - #{x} and the \n"),
								 :name => "foo-#{x}.txt", :mtime => Time.now)
				end
			end
		end
	end
end
end

