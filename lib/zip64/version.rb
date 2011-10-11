module Zip64
	VERSION = [0,0,1]
	def VERSION.to_s
		map { |v| v.to_s }.join('.')
	end
end
