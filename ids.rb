require 'bindata'

#----------- CONSTANTS

DATASET = "wc_day58_3"
#DATASET = "test_log"
PERIOD = 1 # period is 1 sec
K1 = 10 # MAX SIZE OF @pkt 
K2 = 10 # MAX SIZE OF @P
DLY = 40 # if a client is not request for a period of DLY its not a DDOS
ALPHA1 = 0.85
ALPHA2 = 0.85
UP = ALPHA1
DN = 1.0 - ALPHA1
MAXFLASH = 1000
LOGPRD = 100
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
	while i < MAXFLASH do
                i = i +1;
                req = Worldcup98.read(io)
		@pkt.push req
		if req.clientID_ > @max then @max = req.clientID_ end
        end
   end
   def maxCID
	return @max
   end
   def stime
	return @pkt.first.timestamp_
   end
   def etime
	return @pkt.last.timestamp_
   end
   def finished?
	return @ind >=MAXFLASH
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
				@pkt.push Worldcup98.getNew i,e[0]
				@bots[j] = e[1] + BOTCONSTSPEED
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
  @p = Array.new
  def initialize req
     @cid = req.clientID_
     @pkt = Hash.new
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
d "#{x} #{y} #{c}"
	return c
  end
  def method1
	return calcCorrel @pkt.values @pkt.keys	
  end
  def method2
  	return calcCorrel @pkt.values.odd_values,@pkt.values.even_values
  end
  def process
     r1 = method1
     r2 = method2
     @pkt.clear
     @p.push [r1,r2]
     if r1 > UP || r1 < DN then
	l 2,"traffic client #{@cid} is unpredictible in #{@p.size}'th time"
     else
	l 2,"traffic client #{@cid} is predictible in #{@p.size}'th time"
     end
     if @p.size == K2 then
	pb1 = @p.map{|a| a[0]}.sum / K2
	pb2 = @p.map{|a| a[1]}.sum / K2
	if (pb1 >= ALPHA2) then
		l 3,"traffic client #{@cid} is ATTACK by method 1"
	end
	if (pb2 >= ALPHA2) then
		l 3,"traffic client #{@cid} is ATTACK by method 2"
	end
	if (pb1 < ALPHA2 && pb2 < ALPHA2) then
		l 3,"traffic client #{@cid} is not ATTACK pb1=#{pb1} pb2=#{pb2} -- make safe"
		
	end
     end
  end
  def add req
     if !@lst.nil? && req.timestamp_ - @lst > DLY then
	 # mark as safe
	 makesafe
#	 l 1,"Client #{@cid} marked as Safe -- DLY=#{req.timestamp_ - @lst}                      last=#{@lst} now=#{req.timestamp_}"
	 return
     end
     @lst = req.timestamp_
     if @pkt.keys.include? req.timestamp_ then
         @pkt[req.timestamp_] = @pkt[req.timestamp_] + 1
     else
	 @fst = req.timestamp_
         @pkt[req.timestamp_] = 1
     end
     if req.timestamp_ - @fst > 2* K1 then
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
def simulate
	flash = FlashCrowd.new
	l 1,"Dataset #{DATASET} loaded for flash crowded traffic"
	botnet = BotNet.new(flash.maxCID ,BOTSIZE,flash.stime,flash.etime)
	l 1,"BotNet simulator created with size=#{BOTSIZE} and startCID=#{flash.maxCID}"
	i=0
	time = flash.stime
	while !flash.finished? do
	        fls = flash.nxt time
		bot = botnet.nxt time
		time += 1
		(fls | bot).each{ |req|
                        i +=1
			if i>0 && i % LOGPRD == 0 then l 1,"#{i} packets processed" end
			process req
		}
	end
end
#---------- MAIN
simulate
l 0, "sc is =#{$sc.to_s}"
l 0, "rj is =#{$rj.to_s}"
l 0, "pr is =#{$pr.keys.to_s}"
