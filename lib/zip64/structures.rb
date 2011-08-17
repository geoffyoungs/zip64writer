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
			[value].pack(@type.nil? ? options[:default] : @type)
		rescue
			raise "#{value.inspect} is not a valid type for #{self.inspect}"
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

	def to_string
		buf = ''
		fields.each do |f|
			buf << f.encode(self, send(f.name))
		end
		buf
	end
	alias :to_s :to_string

	def size
		to_string.size
	end

	def initialize(options={})
		options.each do |key,val|
			send("#{key}=", val) if respond_to?("#{key}") && respond_to?("#{key}=")
		end
	end
end


class Zip64ExtraField < Block
	ID = 0x0001
	fields ['v', :header_id],
			['v', :header_len],
			['Q', :raw_data_len],
			['Q', :data_len]
end

class LocalFileHeader < Block
	SIG = 0x04034b50
	LEN64 = 0xFFFFFFFF
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
	
	attr_reader :filename, :extra_field
	def to_string
		super + "#{@filename}#{extra_field}"
	end
	def filename=(str)
		self.filename_len = str.size
		@filename = str
	end
	def extra_field=(str)
		self.extra_field_len = str.size
		@extra_field = str
	end
end

class CDFileHeader < Block
	SIG = 0x02014b50
	LEN64 = 0xFFFFFFFF
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
		['v', :filename_len],
		['v', :extra_field_len],
		['v', :file_comment_len],
		['v', :disk_no],
		['v', :internal_file_attributes],
		['V', :external_file_attributes],
		['V', :rel_offset_of_local_header]
	
	attr_reader :filename, :extra_field
	def to_string
		super + "#{@filename}#{extra_field}"
	end
	def filename=(str)
		self.filename_len = str.size
		@filename = str
	end
	def extra_field=(str)
		self.extra_field_len = str.size
		@extra_field = str
	end
end

class Zip64EOCDR < Block
	SIG = 0x02014b50
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
		@file_comment = str
		self.file_comment_len = str.size
	end
end

header = LocalFileHeader.new(:flags => 8,
		:last_mod_file_time => 0,
		:last_mod_file_date => 0,
		:crc32 => 0x57f43c0a,
		:data_len => LocalFileHeader::LEN64,
		:raw_data_len => LocalFileHeader::LEN64,
		:filename => "-",
		:extra_field => "")

header.extra_field = Zip64ExtraField.new(:header_id => Zip64ExtraField::ID,
		:header_len => 16,
		:raw_data_len => 1125200,
		:data_len => 1120697)

STDOUT << header.to_string
