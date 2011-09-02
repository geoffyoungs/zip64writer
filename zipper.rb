#!/usr/bin/env ruby
$:<< '../lib' << 'lib'
require 'http/parser'
require "em-synchrony"
require 'fiber'

require 'zip64/writer'

module Zipper
	module_function
	class FeederFiber
		def self.size
			@fibers && @fibers.size || 0
		end
		def self.each(&block)
			@fibers.each_with_index do |fiber, index|
				block.call(fiber)
				break if index > 50 # Only poll the first X connections
			end if @fibers
		end
		def self.coop
			Zipper::FeederFiber.each do |fiber|
				fiber.resume unless fiber.buffer_full?
			end
		end
		def self.ensure_poll
			return if @pt
			puts "Create timer"
			#@pt = EM.add_periodic_timer(0.02) { coop }
		end
		def self.add(fiber)
			@fibers ||= []
			@fibers.push(fiber)
			#ensure_poll
		end
		def self.remove(fiber)
			@fibers.delete(fiber) if @fibers
			if @fibers.empty? && @pt
				puts "Cancel timer"
				@pt.cancel
				@pt = nil
			end
		end
		attr_reader :fiber, :conn, :head
		class ChunkStream
			def initialize(io)
				@io = io
			end
			def send_data(data)
				@io.send_data("#{data.size.to_s(16)}\r\n")
				@io.send_data(data)
				@io.send_data("\r\n")
			end
			def close_connection_after_writing
				@io.send_data("0\r\n\r\n")
				@io.close_connection_after_writing
			end
		end
		MANIFEST = Dir["/home/geoff/Photos/*.jpg"].sort
		def initialize(conn, head)
			@conn, @head = conn, head

			@fiber = Fiber.new do
				name = "sample"
				writer = Zip64::EventMachineWriter.new(ChunkStream.new(@conn))

				case head.request_url
				when /z64/
					name += "-zip64"
				#when /z32/
				else
					name += '-zip32'
				end

				case head.request_url
				when /russian/
					name += "-russiandolls"
					russiandolls = true
				else
					name += '-nodolls'
					russiandolls = false
				end

				case head.request_url
				when /links/
					name += "-links"
					links = true
				else
					name += '-nolinks'
					links = false
				end

				case head.request_url
				when /limit-(\d+)([kmgt])/i
					class << writer
						attr_accessor :threshold
					end
					name += "-limit-#{$1}#{$2}"
					thresh, factor = $1.to_i, $2
					factor = case factor.downcase
					when 'k'
						1024
					when 'm'
						1024 ** 2
					when 'g'
						1024 ** 3
					when 't'
						1024 ** 4
					else
						1
					end

					writer.threshold = thresh * factor
				else
					#
				end


				writeln("HTTP/1.1 200 OK")
				writeln("Transfer-Encoding: chunked")
				writeln("Content-Type: application/zip")
				writeln('Content-Disposition: attachment; filename="%s.zip"' % name)
				writeln("")

				STDERR.puts "Sending: #{name}.zip"

				manifest = MANIFEST.dup

				no_files_since_yield = 0

				until manifest.empty?
					if buffer_full? or no_files_since_yield > 3
						EM.next_tick { @fiber.resume }
						Fiber.yield
						no_files_since_yield = 0
						next
					else
						no_files_since_yield += 1
					end

					entry = manifest.shift

					File.open(entry, 'rb') { |fp|
						time = Time.now
						name = File.basename(entry)
						info = {:name => name, :mtime => time}
						info[:russiandolls] = [ { :name => ("dup-%s" % name) } ] if russiandolls
						writer.add_entry(fp, info)
						writer.add_link(info[:name], info.merge(:name => 'link-%s' % info[:name])) if links
					}
				end

				writer.close
				FeederFiber.remove(self)
			end

			FeederFiber.add(self)

			@fiber.resume
		end

		def resume
			#STDERR.puts "Resuming #{self.object_id} - #{Time.now.strftime('%H:%M:%S')}"
			@fiber.resume
		end

		def buffer_threshold
			1024 * 50
		end

		def buffer_full?
			#STDERR.puts "Check: #{@conn.get_outbound_data_size} #{buffer_threshold}"
			@conn.get_outbound_data_size > buffer_threshold
		end

		def writeln line
			@conn.send_data("#{line}\r\n")
		end
	end
	class Connection < EM::Connection
		def post_init
			@parser = Http::Parser.new
			@headers = []
			@parser.on_headers_complete = lambda do |headers|
				@headers.push(@parser)
				STDERR.puts "Request for: #{@parser.request_url} #{FeederFiber.size}"
				#STDERR.puts [:head, @parser.http_version, @parser.request_url,
				#  	@parser.status_code, @parser.headers].inspect
			end
			@parser.on_body = lambda do |data|
				STDERR.puts [:body, data].inspect
			end
			@parser.on_message_complete = lambda do
				case @parser.request_url
				when /.zip$/
					@feeder = FeederFiber.new(self, @headers.pop)
				else
					static_page({ :type => 'text/html' }, <<-EOP)
<!DOCTYPE html>
<html>
<head>
	<title>zipper.rb test</title>
</head>
<body>
<h1>Standard Test Zip Archives</h1>
<ul>
	<li><a href="/sample-z32-limit-200m.zip">Standard Zip File</a> - Zip32, Threshold kicks in at 200Mb</li>
	<li><a href="/sample-z64.zip">Zip file with zip64&trade;</a> - Zip64 extensions on everything</li>
	<li><a href="/sample-links-z64.zip">Zip file with zip64&trade;</a> - Zip64 extensions on everything + links</li>
	<li><a href="/sample-z32-limit-800m.zip">Standard Zip File</a> - No fanciness</li>
	<li><a href="/sample-z32-links-limit-800m.zip">Standard Zip File</a> - No fanciness except links</li>
</ul>
<h1>Russian Doll Test Zip Archives</h1>
<ul>
	<li><a href="/sample-russian-z32-limit-200m.zip">Standard Zip File</a> - Zip32, Threshold kicks in at 200Mb, plus dolls</li>
	<li><a href="/sample-russian-z64.zip">Zip file with zip64&trade;</a> - Zip64 extensions on everything, plus dolls</li>
	<li><a href="/sample-russian-links-z64.zip">Zip file with zip64&trade;</a> - Zip64 extensions on everything, plus dolls, + links</li>
	<li><a href="/sample-russian-z32-limit-800m.zip">Standard Zip File</a> - Only dolls</li>
	<li><a href="/sample-russian-z32-links-limit-800m.zip">Standard Zip File</a> - Only dolls & links</li>
</ul>
</body>
</html>
EOP
				end
			end
		end

		def static_page(info, data)
			send_data("HTTP/1.1 200 OK\r\n")
			send_data("Content-Type: #{info[:type]}\r\n") if info[:type]
			send_data("Content-Length: #{data.size}\r\n")
			send_data("\r\n")
			return if @parser.http_method == "HEAD"
			send_data(data)
			close_connection_after_writing
		end

		def unbind
			STDERR.puts "Client disconnected"
			FeederFiber.remove(@feeder) if @feeder
		end

		def receive_data(data)
			@parser << data
		rescue HTTP::Parser::Error
			close_connection_after_writing rescue true
		end
	end
end

address = '0.0.0.0'
port    = 9090
EM.synchrony do
	trap("INT")  { EM.stop }
	trap("TERM") { EM.stop }

	EM.epoll

	#load_config(options[:config])
	#load_plugins

	#EM.set_effective_user(options[:user]) if options[:user]
	#EM.add_periodic_timer(0.02) do
	#	Zipper::FeederFiber.each do |fiber|
	#		fiber.resume unless fiber.buffer_full?
	#	end
	#end

	EM.start_server(address, port, Zipper::Connection) do |conn|
		# init conn?
	end

end


