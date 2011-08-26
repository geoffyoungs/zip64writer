
require 'zip64/structures'
require 'stringio'
def find_block_type sig
	Zip64.constants.each do |nam|
		klass = Zip64.const_get(nam)
		if klass.respond_to?(:constants) && klass.constants.include?('SIG')
			if sig == klass::SIG
				return klass
			end
		end
	end
	nil
end

def zip_debug(arg)

File.open(arg, "rb") do |fp|
	until fp.eof?
		until fp.eof? or (fp.tell%2).zero?
			fp.getc
		end
		bs = fp.tell
		STDOUT.write(sprintf(".%-16i", bs))
		sig = fp.read(4).unpack('V').first
		klass = find_block_type sig

		if klass
			o = klass.read_from(fp, 1)
			o.signature = sig
			o.describe(STDOUT)
			
			case o
			when Zip64::LocalFileHeader
				filename = fp.read(o.filename_len)
				extra = fp.read(o.extra_field_len)

				data_len = o.data_len

				unless extra.empty?
					if o.data_len == Zip64::LEN64
						info = Zip64::Zip64ExtraField.read_from(StringIO.new(extra), 0)
						info.describe(STDOUT)
						data_len = info.data_len
					end
				end

				data = fp.read(data_len)
				p [:filename, filename]
				p [:extra, extra]
				if data.size > 50
					data = data[0..50]+"(#{data.size} bytes, truncated)"
				end
				p [:data, data]
			end
		else
			puts sprintf('%16s %16i', sig.to_s(16), sig) if sig
		end
	end
end

end


