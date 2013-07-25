require 'bindata'

#----------- CONSTANTS

#DATASET = "wc_day58_3"
DATASET = "test_log"
PERIOD = 1 # period is 1 sec

#----------- CLASSES
class Worldcup98 < BinData::Record
  endian :big

  uint32 :timestamp_
  uint32 :clientID_
  uint32 :objectID_
  uint32 :size_
  uint8 :method_
  uint8 :status_
  uint8 :type_
  uint8 :server_

  def p
	l 1,"#{timestamp_} #{clientID_} #{objectID_} #{size_} #{method_} #{status_} #{type_} #{server_}"
  end
end
#---------- VARIABLES
@sc = Array.new	# safe client


#---------- FUNCTIONS
def d(s)
	color_s = "\033[1m\033[33m"
	color_f = "\033[0m\033[22m"
	puts  "#{color_s}#{Time.new.strftime("%H:%M:%S")} #{s.to_s}#{color_f}"
end
def l(n,s)
	color_s = "\033[1m\033[34m"
	color_f = "\033[0m\033[22m"
	space = "   " * n
	puts  "#{color_s}#{Time.new.strftime("%H:%M:%S")} #{space} #{s.to_s}#{color_f}"
end
def e(n,s)
	color_s = "\033[1m\033[31m"
	color_f = "\033[0m\033[22m"
	space = "   " *n
	puts  "#{color_s}#{Time.new.strftime("%H:%M:%S")} #{space} #{s.to_s}#{color_f}"
end

def process req
	req.p
#	if ! @sc.includes? req.clientID_ then
		
#	end
end

def simulate
	io = File.open(DATASET)
	i=0
	while !io.eof? do
        	i = i +1;
	        req = Worldcup98.read(io)
		process req
	end
end
#---------- MAIN
simulate
