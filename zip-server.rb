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

class ChunkedStreaming < Goliath::API
  def on_close(env)
    env.logger.info "Connection closed."
  end

  BUF = (1024 * 1024) # 1 mb

  def response(env)
	env.logger.info(env.inspect)

	manifest = Dir["/media/nas/StockArt/*.jpg"]

	writer = Zip64::EventMachineWriter.new(env)

	send_next = lambda do
		entry = manifest.shift
		writer.add_entry(File.open(entry), :name => File.basename(entry))
	end

	until manifest.empty?
		if env.request.conn.get_outbound_data_size >= BUF
			EventMachine.next_tick(&send_next)
		else
			send_next
		end
	end

	writer.close
    env.chunked_stream_close

    headers = { 'Content-Type' => 'application/zip', 'X-Stream' => 'Goliath' }
    chunked_streaming_response(200, headers)
  end
end
