#!/usr/bin/env ruby
$:<< '../lib' << 'lib'

#
# A simple HTTP streaming API which returns a 200 response for any GET request
# and then emits numbers 1 through 10 in 1 second intervals using Chunked
# transfer encoding, and finally closes the connection.
#
# Chunked transfer streaming works transparently with both browsers and
# streaming consumers.
#

require 'goliath'
require 'zip64/writer'

class ZipStream < Goliath::API
	def on_close(env)
		env.logger.info "Connection closed."
	end

	BUF = (1024 * 1024) # 1 mb

	class ZipIt
		class Writer < Zip64::ZipWriter
			attr_accessor :buffer
			def write_raw(bytes)
				@buffer << bytes
				@offset += bytes.size
			end
		end

		def initialize(env, filelist)
			
		end

		def each
			
		end
	end

	def response(env)
		env.logger.info(env.inspect)
		env.logger.info("Self: "+self.inspect)
		env.logger.info("Instance variables: "+instance_variables.sort.inspect)

		filename = "sample.zip"
		manifest = Dir["/home/geoff/Photos/*.jpg"]

		writer = Zip64::GoliathWriter.new(env)

		pt = EM.add_periodic_timer(0.1) do
			entry = manifest.shift
			if entry
				File.open(entry, 'rb') { |fp|
					time = Time.now
					#env.logger.info("Writing: #{entry}")
					writer.add_entry(fp, :name => File.basename(entry), :mtime => time)
				}
			else
				env.logger.info("Finishing up: #{entry}")
				writer.close
				env.chunked_stream_close
				pt.cancel
			end
		end

		#send_next = lambda do
		#	entry = manifest.shift
		#	writer.add_entry(File.open(entry), :name => File.basename(entry))
		#end

		#until manifest.empty?
		#	if env.request.conn.get_outbound_data_size >= BUF
		#		EventMachine.next_tick(&send_next)
		#	else
		#		send_next
		#	end
		#end

		#writer.close
		#env.chunked_stream_close

		headers = { 'Content-Type' => 'application/zip', 
					'X-Stream' => 'Goliath', 
					'Content-Disposition' => 'attachment; filename="%s"' % filename }
		chunked_streaming_response(200, headers)
	end
end
