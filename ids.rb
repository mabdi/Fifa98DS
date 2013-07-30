require 'bindata'

#----------- CONSTANTS

DATASET = "wc_day58_3"
#DATASET = "test_log"
PERIOD = 1 # period is 1 sec
K1 = 10 # MAX SIZE OF @pkt 
K2 = 10 # MAX SIZE OF @P
DLY = 40 # if a client is not request for a period of DLY its not a DDOS
MTD = 1
ALPHA1 = 0.85
ALPHA2 = 0.85
UP = ALPHA1
DN = 1.0 - ALPHA1
FLASHDUR = 30
LOGPRD = 2000
LOGLEVEL = 5
BOTSIZE = 100
BOTTYPE = :const
BOTCONSTSPEED = 1
BOTACTIVEFROM = 0 # a bot instance start after this
BOTACTIVERAND = 0 # a bot instance start sending packet from a random number between 0 and BOTACTIVERAND (will sum with BOTACTIVEFROM)
#---------- VARIABLES
$sc = Array.new # safe client
$rj = Array.new # Rejected trafic
$pr = Hash.new # Processing trafic
#----------- CLASSES
class Array
  def sum
    self.reduce(:+)
  end
  def odd_values
    self.values_at(* self.each_index.select {|i| i.odd?})
  end
  def even_values
    self.values_at(* self.each_index.select {|i| i.even?})
  end
end
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
	d "#{timestamp_} #{clientID_} #{objectID_} #{size_} #{method_} #{status_} #{type_} #{server_}"
  end
  def self.getNew time,cid
	ins = Worldcup98.new
	ins.timestamp_ = time
	ins.clientID_ = cid
	return ins
  end
end
class FlashCrowd
   @pkt
   @max
   @ind

   def initialize
	@pkt = Array.new
	@ind = 0
	io = File.open(DATASET)
	i = 0
	@max = -1
	req = Worldcup98.read(io)
	start = req.timestamp_
	while req.timestamp_ < start + FLASHDUR do
                i = i +1;
                req = Worldcup98.read(io)
		@pkt.push req
		if req.clientID_ > @max then @max = req.clientID_ end
        end
   end
   def maxCID
	return @max
   end
   def size
	return @pkt.size
   end
   def stime
	return @pkt.first.timestamp_
   end
   def etime
	return @pkt.last.timestamp_
   end
   def finished?
	return @ind >=@pkt.size
   end
   def nxt time
	ret = Array.new
    	while @ind < @pkt.size && @pkt[@ind].timestamp_ == time do
		ret.push @pkt[@ind]
		@ind +=1
	end
	return ret
   end
end
class BotNet
   @pkt
   @bots
   @ind
   def  initialize startID,n,startTime,endTime
	@bots = (startID..(startID + n)).map{|x| [x, BOTACTIVEFROM + rand(BOTACTIVERAND).to_i]}
	@ind =0
	case BOTTYPE
		when :const then const startTime,endTime
	end
   end

   def const startTime,endTime
	@pkt = Array.new
	for i in startTime..endTime
		@bots.each_with_index{ |e,j|
			if e[1] + startTime == i then
				BOTCONSTSPEED.ceil.times{ |z|
					@pkt.push Worldcup98.getNew i,e[0]
				}
				@bots[j] = [e[0], e[1] + (1.0 / BOTCONSTSPEED).ceil ]
			end
		}
	end
   end

   def nxt time
	ret = Array.new
        while @ind < @pkt.size && @pkt[@ind].timestamp_ == time do
                ret.push @pkt[@ind]
                @ind +=1
        end
        return ret
   end
end
class DSRequest
  @cid
  @pkt 
  @lst 
  @fst
  @p
  def initialize req
     @cid = req.clientID_
     @pkt = Hash.new
     @fst = req.timestamp_
     @p = Array.new
  end
  def makesafe
	$sc.push @cid
        $pr.delete @cid
  end
  def makeAttack
	$rj.push @cid
	$pr.delete @cid
  end
  def calcCorrel x,y
	sx = x.sum
	sy = y.sum
	sx2 = x.map{|n| n**2 }.sum
	sy2 = y.map{|n| n**2 }.sum
	sxy = x.zip(y).map{|a,b| a*b}.sum
	n = x.size
	c =  (n * sxy - sx * sy ) / (Math.sqrt((n*sx2 - sx**2 )*(n*sy2 - sy**2)))
	return c
  end
  def method1
	return calcCorrel @pkt.values,@pkt.keys	
  end
  def method2
  	return calcCorrel @pkt.values.odd_values,@pkt.values.even_values
  end
  def process
     r =0
     if MTD == 1 then
     	r = method1.abs
     else
     	r = method2.abs
     end
b binding
     @pkt.clear
     @p.push r
=begin
     if r > UP || r < DN then
	l 2,"traffic client #{@cid} is unpredictible in #{@p.size}'th time"
     else
	l 2,"traffic client #{@cid} is predictible in #{@p.size}'th time"
     end
=end
     if @p.size == K2 then
b binding
	pb = @p.sum / K2
	if (pb >= ALPHA2) then
		l 3,"traffic client #{@cid} is ATTACK by method #{MTD} pb=#{pb}"
		makeAttack
	else
		l 3,"traffic client #{@cid} is not ATTACK pb=#{pb} -- make safe"
		makesafe
	end
     end
  end
  def cleanup now
     if !@lst.nil? && (now - @lst > DLY) then
         makesafe
         return
     end
  end
  def add req
     cleanup req.timestamp_
     @lst = req.timestamp_
     if @pkt.keys.include? req.timestamp_ then
         @pkt[req.timestamp_] = @pkt[req.timestamp_] + 1
     else
         @pkt[req.timestamp_] = 1
     end
     if req.timestamp_ - @fst >  K1 then
        process 
     end
  end
end
#---------- FUNCTIONS
def d(s)
	color_s = "\033[1m\033[33m"
	color_f = "\033[0m\033[22m"
	line= (caller.first.split ":")[1]
	puts  "#{color_s}#{Time.new.strftime("%H:%M:%S")} line:#{line} -- #{s.to_s}#{color_f}"
end
def l(n,s)
   if n <= LOGLEVEL then
	color_s = "\033[1m\033[34m"
	color_f = "\033[0m\033[22m"
	space = "   " * n
	puts  "#{color_s}#{Time.new.strftime("%H:%M:%S")} #{space} #{s.to_s}#{color_f}"
   end
end
def e(n,s)
	color_s = "\033[1m\033[31m"
	color_f = "\033[0m\033[22m"
	space = "   " *n
	puts  "#{color_s}#{Time.new.strftime("%H:%M:%S")} #{space} #{s.to_s}#{color_f}"
end
def b2 a
	color_s = "\033[1m\033[31m"
        color_f = "\033[0m\033[22m"
	line= (caller.first.split ":")[1]
        puts  "#{color_s}#{Time.new.strftime("%H:%M:%S")} line:#{line} -- #{a.join '; '}#{color_f}"
	begin
	  s = gets
	  if s.downcase == "!" then break end
	  if s.start_with? "-" then eval s[1..-1] 
	  else eval ("puts #{s}"),binding end
	end while true
end
def b bind
        color_s = "\033[1m\033[31m"
        color_f = "\033[0m\033[22m"
        line= (caller.first.split ":")[1]
	vars = eval('local_variables',bind).map{|v| "#{v.to_s}= #{eval(v.to_s,bind)}"}.join ";"
        puts  "#{color_s}#{Time.new.strftime("%H:%M:%S")} line:#{line} -- #{vars}#{color_f}"
	begin
		print "\033[31m"
	        begin
		  print "dbg> "
	          s = gets.strip
	          if s == "" then break end
	          if s.start_with? "-" then eval s[1..-1],bind
	          else eval ("puts (#{s}).to_s"),bind end
		rescue => e
		  puts "Error Ecurred: \033[33m#{e.message}\033[0m"
	        end while true
	ensure
		print "\033[0m"
	end
end
def drop req
		
end
def allow req

end
def process req
	if $sc.include? req.clientID_ then
		allow req
		return
	end
	if $rj.include? req.clientID_ then
		drop req
		return
	end
	# processs
	if !$pr.keys.include? req.clientID_ then
		$pr[req.clientID_] = DSRequest.new(req)
	end
	$pr[req.clientID_].add req
end
def cleanup time
	$pr.each_value{ |v| v.cleanup time }
end
def simulate
	flash = FlashCrowd.new
	l 1,"Dataset #{DATASET} loaded for flash crowded traffic size=#{flash.size} TimeDuration=#{FLASHDUR} seconds"
	botnet = BotNet.new(flash.maxCID ,BOTSIZE,flash.stime,flash.etime)
	l 1,"BotNet simulator created with size=#{BOTSIZE} and startCID=#{flash.maxCID}"
	i=0
	time = flash.stime
	while !flash.finished? do
		l 1,"Now= #{Time.at(time).strftime("%Y-%m-%d %H:%M:%S")}"
	        fls = flash.nxt time
		bot = botnet.nxt time
		time += 1
		(fls | bot).each{ |req|
                        i +=1
			if i>0 && i % LOGPRD == 0 then l 1,"#{i} packets processed" end
			process req
		}
		if (time % DLY == 0) then
			cleanup time
		end
	end
	l 1,"#{i} packets processed"
end
#---------- MAIN
simulate
b binding
