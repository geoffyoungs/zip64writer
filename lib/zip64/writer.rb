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

	def ensure_metadata(io, info)
		info = info.dup

		info[:mtime] ||= Time.now

		info[:name] ||= File.basename(io.path) if io.respond_to?(:path) && io.path
		info[:name] ||= "file-#{@dir_entries.size+2}.dat"

		info
	end

	def make_entry32(io, info, data, crc)
		header = LocalFileHeader.new(
			:flags => (1<<11),
			:compression => 0,
			:last_mod_file_time => Zip64.time_to_msdos_time(info[:mtime]),
			:last_mod_file_date => Zip64.date_to_msdos_date(info[:mtime]),
			:crc32 => crc,
			:data_len => data.size,
			:raw_data_len => data.size,
			:filename => info[:name])

		header.extra_field = ''

		header
	end

	def make_entry64(io, info, data, crc)
		header = LocalFileHeader.new(
			:flags => 0,
			:last_mod_file_time => Zip64.time_to_msdos_time(info[:mtime]),
			:last_mod_file_date => Zip64.date_to_msdos_date(info[:mtime]),
			:crc32 => crc,
			:data_len => LEN64,
			:raw_data_len => LEN64,
			:filename => info[:name])

		extra = Zip64ExtraField.new(
			:header_id => Zip64ExtraField::ID,
			:header_len => 16,
			:raw_data_len => data.size,
			:data_len => data.size)

		header.extra_field = extra

		header
	end

	def make_entry(io, info, data, crc)
		if info[:use] == 64 || @offset + data.size > self.threshold
			header = make_entry64(io, info, data, crc)
		else
			header = make_entry32(io, info, data, crc)
		end
	end

	def add_entry(io, info)
		info = ensure_metadata(io, info)

		data = io.read.to_s
		crc = Zlib.crc32(data, 0)

		# XXX: this doesn't fit well with the planned usage :(
		entry = { :offset => @offset, :len => data.size }
		@dir_entries << entry

		header = make_entry(io, info, data, crc)

		entry[:zip64] = header.zip64?

		if info[:russiandolls]
			first_header = header
			last_header = header

			info[:russiandolls].each_with_index do |doll,index|
				io.rewind
				doll_header = make_entry(io, info.merge(doll), data, crc)
				doll_prefix = [0x4343, doll_header.size].pack('vv')

				if (doll_header.to_string.size + doll_prefix.size) +
						first_header.to_string.size > local_header_max
					STDERR.puts "Can't add any more dolls! Dolls #{index}-#{dolls.size-1} omitted."
				else
					offset = @offset + first_header.to_string.size + doll_prefix.size
					last_header.extra_field << doll_prefix << doll_header
					@dir_entries << { 
						:offset => offset, 
						:len => data.size, 
						:local_header => doll_header,
						:zip64 => doll_header.zip64?
					}
					last_header = doll_header
				end
			end
		end

		entry[:local_header] = header

		# write output
		write header.to_string

		# write data (& any compression?)
		write data


		# write descriptor - not need with current strategy
		# write DD64.new(:crc32 => crc,
		#			:data_len => data.size,
		#			:raw_data_len => data.size).to_string
	end

	def local_header_max
		1024 * 64
	end

	def threshold
		1024 * # kb
		1024 * # mb
		1024 * # gb
		2 - local_header_max
	end

	def write_central_directory
		align
		@central_directory_offset = @offset

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
			#p [:header, header.filename, header.crc32, header.last_mod_file_time, header.last_mod_file_date]
			write CDFileHeader.new(
				:flags => header.flags,
				:compression => header.compression,
				:made_by => (3 << 8),
				:last_mod_file_time => header.last_mod_file_time,
				:last_mod_file_date => header.last_mod_file_date,
				:crc32 => header.crc32,
				:data_len => entry[:zip64] ? LEN64 : len,
				:raw_data_len => entry[:zip64] ? LEN64 : len,
				:filename => header.filename,
				:extra_field => entry[:zip64] ? extra_field.to_string : '',
				:file_comment => '',
				:disk_no => entry[:zip64] ? 0xffff : 0,
				:internal_file_attributes => 0,
				:external_file_attributes => 0,
				:rel_offset_of_local_header => entry[:zip64] ? LEN64 : offset
			).to_string
		end

		# Central Directory Size
		@central_directory_size = @offset - @central_directory_offset
	end

	def write_zip64_end_of_central_directory
		#align
		@zip64_central_directory_offset = @offset

		write Zip64EOCDR.new(
			:made_by => 3 << 8,
			:this_disk_no => 0,
			:disk_with_cd_no => 0,
			:total_no_entries_on_this_disk => @dir_entries.size,
			:total_no_entries => @dir_entries.size,
			:size_of_cd => @central_directory_size,
			:offset_of_cd_wrt_disk_no => @central_directory_offset,
			:data => ''
		).to_string
	end

	def write_zip64_end_of_central_directory_locator
		#align
		write Zip64EOCDL.new(
			:disk_with_z64_eocdr => 0,
			# Assume relative offset is relative to disk, as
			# is case elsewhere in Zip spec
			:relative_offset => @zip64_central_directory_offset,
			:no_disks => 1
		).to_string
	end

	def write_end_of_central_directory_record
		#align
		write EOCDR.new(
			:disk_no => 0,
			:disk_with_cd_no => 0,
			:total_entries_in_local_cd => @dir_entries.size,
			:total_entries => @dir_entries.size,
			:cd_size => @central_directory_size,
			:offset_to_cd_start => @central_directory_offset,
			:file_comment => ''
		).to_string
	end

	def close
		#[archive decryption header]
		# ignore
		#[archive extra data record]
		# ignore

		#[central directory]
		write_central_directory()

		if @dir_entries.any? { |entry| entry[:zip64] }
			#[zip64 end of central directory record]
			write_zip64_end_of_central_directory()

			#[zip64 end of central directory locator]
			write_zip64_end_of_central_directory_locator()
		end

		#[end of central directory record]
		write_end_of_central_directory_record()

		write_last()
	end

	def self.get_io_size(io)
		if io.respond_to?(:stat)
			size = io.stat.size
		elsif io.respond_to?(:size)
			size = io.size
		else
			pos = io.tell
			io.seek(0, IO::SEEK_END)
			size = io.tell
			io.seek(pos, IO::SEEK_START)
		end
		size
	end

	def self.predict_size64(files)
		file_overhead = LocalFileHeader.base_size +
				Zip64ExtraField.base_size

		cd_overhead = CDFileHeader.base_size +
			Zip64CDExtraField.base_size

		total = 0
		names_size = 0
		dolls = 0
		doll_names_size = 0
		files.each do |file|
			names_size += file[:name].size
			total += get_io_size(file[:io]) + file[:name].size + file_overhead

			if file[:russiandolls]
				file[:russiandolls].each do |doll|
					total += doll[:name].size + file_overhead + 4
					dolls += 1
					doll_names_size += doll[:name].size
				end
			end
		end

		until (total%4).zero?
			total += 1
		end

		total += files.size * cd_overhead
		total += names_size

		total += dolls * cd_overhead
		total += doll_names_size

		total += EOCDR.base_size + Zip64EOCDL.base_size + Zip64EOCDR.base_size

		total
	end

	protected
	def align
		until (@offset % 4).zero?
			write_raw "\0"
		end
	end
	def write(bytes)
		bytes = bytes.to_string unless bytes.is_a?(String)
		write_raw(bytes)
	end
	def write_raw(bytes)
		#STDERR.puts "Write: #{'%8i' % bytes.size} @#{'%08i' % @offset}"
		@io << bytes
		@offset += bytes.size
	end
	def write_last(bytes=nil)
		bytes = bytes.to_string if bytes.respond_to?(:to_string)
		write_raw(bytes) unless bytes.nil? or bytes.empty?
	end

	def self.test
		files = []
		15.times do |x|
			files << { :name => ("foo-%02i.txt" % x), :io => StringIO.new("Foo is #{x} and #{x * x}") }
			info = files.last
			(x*500).to_i.times do |y|
				files.last[:io].puts "And some more lines about blah - we are foo #{x}"
			end
			files.last[:io].rewind

			(rand()*15).to_i.times do |n|
				info[:russiandolls] ||= []
				info[:russiandolls] << { :name => ("%s-doll%02i.txt" % [info[:name],n]) }
			end #if (i % 2).zero?
		end

		x = predict_size64(files)
		File.open("test.zip", "w") do |fp|
			ZipWriter.new(fp) do |writer|
				i = 0
				files.each do |info|
					info = {:mtime => Time.now, :use => (i < 3 ? 32 : 64)}.merge(info)

					writer.add_entry(info[:io], info)
					#exit
					#p info
					i += 1
				end
			end
			p [:guess, x, :actual, fp.tell, :diff, fp.tell - x]
		end
	end
end
class GoliathWriter < ZipWriter
	def write_raw(bytes)
		@io.chunked_stream_send(bytes)
		@offset += bytes.size
	end
end
class EventMachineWriter < ZipWriter
	def write_raw(bytes)
		@io.send_data(bytes)
		@offset += bytes.size
	end
	def write_last(bytes=nil)
		bytes = bytes.to_string if bytes.respond_to?(:to_string)
		write_raw(bytes) unless bytes.nil? or bytes.empty?
		@io.finish		
	end
end
end

