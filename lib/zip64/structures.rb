#/usr/bin/env ruby

class Block
	class FieldFormat
		def self.from(line)
			case line
			when Array
				new(*line)
			when self
				line
			else
				raise "#{line.inspect} is not a valid field"
			end
		end

		attr_reader :type, :name
		def initialize(type, name, options = {})
			if options.is_a?(Hash)
			else
				val, options = options, {}
				options[:default] = val
			end
			@type, @name, @options = type, name, options
		end

		def encode(object, value)
			val = value || @options[:default]
			[val].pack(@type).zip64_force_encoding("ASCII-8BIT")
		rescue
			raise "#{value.inspect} (#{val.inspect}?) is not a valid type for #{self.inspect}"
		end
	end
	class << self
		# Reader mode:
		# With no arguments returns the fields defined for this class
		#
		# Writer mode:
		# If args is not empty then each argument is passed to FieldFormat.from(arg)
		# to convert to a FieldFormat object.
		#
		# Also accessors are defined
		def fields *args
			if args.empty?
				@fields
			else
				@fields = args.map { |arg| FieldFormat.from(arg) }
				@fields.each { |f| attr_accessor(f.name) }
			end
		end
	end

	def fields
		self.class.fields()
	end

	def self.base_size
		fields.inject(0) { |t, f| size_of(f.type) + t }
	end

	def read_field_from(fp, field)
		if (sz = size_of(field.type)).nonzero?
			val = fp.read(sz).unpack(field.type).first
			send("#{field.name}=", val)
		else
			fn = "#{field.name}_len"
			if field.type == "A*" && o.respond_to?(fn) && o.send(fn)
				send("#{field.name}=", fp.read(o.send(fn)))
			else
				puts "#{field.name} un-fetchable"
			end
		end
	end

	def self.read_from(fp, offset)
		o = new()
		fields[offset..-1].each do |field|
			next if o.respond_to?(:skip_read?) && o.skip_read?(field)
			o.read_field_from(fp, field)
		end
		o
	end
	def describe(io)
		io.puts "---- #{self.class.name}"
		fields.each do |field|
			val = send(field.name)
			if val.nil?
				io.puts sprintf("%33s %s", 'NULL', field.name)
			else
				io.puts sprintf("%16s %16i %2i %s", val.to_s(16), val,
								size_of(field.type), field.name)
			end
		end
	end


	def self.size_of(type)
		case type
		when 'C', 'c'
			1
		when 'v'
			2
		when 'V'
			4
		when 'Q'
			8
		else
			0
		end
	end
	def size_of(type)
		self.class.size_of(type)
	end

	def to_string
		buf = ''.zip64_force_encoding("ASCII-8BIT")
		fields.each do |f|
			buf << pack_field(f)
		end
		buf
	end
	alias :to_s :to_string

	def pack_field(field)
		field.encode(self, send(field.name))
	end

	def size
		to_string.size
	end

	def initialize(options={})
		options.each do |key,val|
			send("#{key}=", val) if respond_to?("#{key}") && respond_to?("#{key}=")
		end
	end
end

module Zip64

LEN64 = 0xFFFFFFFF
module Flags
	ENCRYPTED = 1 << 0
	CRC_IN_CD = 1 << 3
	UTF8      = 1 << 11
end
module Compression
	NONE      = 0
end


class Zip64ExtraField < Block
	ID = 0x0001
	fields ['v', :header_id],
			['v', :header_len],
			['Q', :raw_data_len],
			['Q', :data_len]
	def to_s; to_string; end
end

class ::String
	def zip64_force_encoding(what)
		respond_to?(:force_encoding) and force_encoding(what) or self
	end
end

class LocalFileHeader < Block
	SIG = 0x04034b50

	fields ['V', :signature, SIG],
		['v', :version, 45],
		['v', :flags, 0],
		['v', :compression, 0],
		['v', :last_mod_file_time],
		['v', :last_mod_file_date],
		['V', :crc32],
		['V', :data_len],
		['V', :raw_data_len],
		['v', :filename_len],
		['v', :extra_field_len]

	def zip64?
		data_len == LEN64 && raw_data_len == LEN64
	end

	def version
		zip64? ? 45 : 10
	end

	attr_reader :filename
	def to_string
		extra = extra_field_str
		self.extra_field_len = extra.size
		super + "#{@filename}#{extra}"
	end
	def	to_s
		to_string
	end
	def filename=(str)
		str = str.dup.zip64_force_encoding('ASCII-8BIT')
		self.filename_len = str.size
		@filename = str
	end
	def extra_field=(str)
		case str
		when Array
			@extra_field = str
		else
			@extra_field = [str]
		end
	end
	def extra_field
		(@extra_field ||= [])
	end
	def extra_field_str
		buf = ''.zip64_force_encoding('ASCII-8BIT')
		extra_field.each do |field|
			if field.respond_to?(:to_string)
				buf << field.to_string.zip64_force_encoding('ASCII-8BIT')
			else
				buf << field.to_s.zip64_force_encoding('ASCII-8BIT')
			end
		end
		buf
	end
end

class CDFileHeader < Block
	SIG = 0x02014b50
	fields ['V', :signature, SIG],
		['v', :made_by],
		['v', :version, 45],
		['v', :flags, 0],
		['v', :compression, 0],
		['v', :last_mod_file_time],
		['v', :last_mod_file_date],
		['V', :crc32, 0],
		['V', :data_len],
		['V', :raw_data_len],
		['v', :filename_len], # auto
		['v', :extra_field_len], # auto
		['v', :file_comment_len], #
		['v', :disk_no],
		['v', :internal_file_attributes],
		['V', :external_file_attributes],
		['V', :rel_offset_of_local_header]

	def zip64?
		data_len == LEN64 && raw_data_len == LEN64
	end

	def version
		zip64? ? 45 : 10
	end

	attr_reader :filename, :extra_field, :file_comment
	def to_string
		super + "#{@filename}#{extra_field}#{file_comment}"
	end
	def file_comment=(str)
		str = str.zip64_force_encoding('ASCII-8BIT')
		self.file_comment_len = str.size
		@file_comment = str
	end
	def filename=(str)
		str = str.zip64_force_encoding('ASCII-8BIT')
		self.filename_len = str.size
		@filename = str
	end
	def extra_field=(str)
		str = str.zip64_force_encoding('ASCII-8BIT')
		self.extra_field_len = str.size
		@extra_field = str
	end
end

class Zip64CDExtraField < Block
	SIG = 0x0001
	fields ['v', :signature, SIG],
		['v', :size],
		['Q', :raw_data_len],
		['Q', :data_len],
		['Q', :relative_offset],
		['V', :disk_no]
	def to_string
		@size = 0
		fields.each { |field| @size += size_of(field.type) }
		@size -= 4
		super
	end
end

class UnixExtraField < Block
	SIG = 0x000d
	fields ['v', :signature, SIG],
		['v',  :size],
		['V',  :atime],
		['V',  :mtime],
		['v',  :uid],
		['v',  :gid],
		['A*', :data, '']

	def to_string
		@size = @data.to_s.size
		fields.each { |field| @size += size_of(field.type) }
		@size -= 4
		super
	end
end

class ExtendedTimestampField < Block
	SIG = 0x5455
	fields ['v', :signature, SIG],
		['v',  :size],
		['C',  :info_bits],
		['V',  :mtime],
		['V',  :atime],
		['V',  :ctime]
	def	skip_read?(field)
		case field.name
		when :mtime
			(@info_bits&1).zero?
		when :atime
			(@info_bits&2).zero?
		when :ctime
			(@info_bits&4).zero?
		else
			false
		end
	end
end

class InfoZipNewUnixExtraField < Block
	SIG = 0x7875
	fields ['v', :signature, SIG],
		['v', :size],
		['C', :version],
		['C', :uid_size],
		['V', :uid],
		['C', :gid_size],
		['V', :gid]
	MAP = { 1 => 'C', 2 => 'v', 4 => 'V'}

	def pack_field(field)
		case field.name
		when :uid
			type = MAP[@uid_size]
			[@uid].pack(type).zip64_force_encoding('ASCII-8BIT')
		when :gid
			type = MAP[@gid_size]
			[@gid].pack(type).zip64_force_encoding('ASCII-8BIT')
		else
			super
		end
	end

	def read_field_from(fp, field)
		case field.name
		when :uid
			type = MAP[@uid_size]
			@uid = fp.read(@uid_size).unpack(type).first
		when :gid
			type = MAP[@gid_size]
			@gid = fp.read(@gid_size).unpack(type).first
		else
			super
		end
	end
end

class DigSig < Block
	SIG = 0x05054b50
	fields  ['V', :signature, SIG],
		['v', :size],
		['A*', :data]
	def to_string
		@size = @data.size
		super
	end
end

class DD64 < Block
	SIG = 0x08074b50
	fields  ['V', :signature, SIG],
		['V', :crc32, 0],
		['Q', :data_len],
		['Q', :raw_data_len]
end

class Zip64EOCDR < Block
#	SIG = 0x02014b50
	SIG = 0x06064b50
	fields ['V', :signature, SIG],
		['Q', :record_len],
		['v', :made_by],
		['v', :version, 45],
		['V', :this_disk_no],
		['V', :disk_with_cd_no],
		['Q', :total_no_entries_on_this_disk],
		['Q', :total_no_entries],
		['Q', :size_of_cd],
		['Q', :offset_of_cd_wrt_disk_no]
		['A*', :data, '']
	def to_string
		@record_len = @data.to_s.size - 12
		fields.each { |field| @record_len += size_of(field.type) }
		super
	end
end

class Zip64EOCDL < Block
	SIG = 0x07064b50
	fields ['V', :signature, SIG],
		['V', :disk_with_z64_eocdr],
		['Q', :relative_offset],
		['V', :no_disks]
end

class EOCDR < Block
	SIG = 0x06054b50
	fields ['V', :signature, SIG],
		['v', :disk_no],
		['v', :disk_with_cd_no],
		['v', :total_entries_in_local_cd],
		['v', :total_entries],
		['V', :cd_size],
		['V', :offset_to_cd_start],
		['v', :file_comment_len]
	attr_reader :file_comment
	def to_string
		super + "#{@file_comment}"
	end
	def file_comment=(str)
		ctr = str.zip64_force_encoding('ASCII-8BIT')
		@file_comment = str
		self.file_comment_len = str.size
	end
end

end


