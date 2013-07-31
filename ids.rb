require 'bindata'
require "readline" # for debugging porpuse

#----------- CONSTANTS

DATASET = "wc_day58_3"
#DATASET = "test_log"
PERIOD = 1 # period is 1 sec
K1 = 10 # MAX SIZE OF @pkt 
K2 = 3 # MAX SIZE OF @P
DLY = 15 # if a client is not request for a period of DLY its not a DDOS
MTD = 1
ALPHA1 = 0.85
ALPHA2 = 0.95
UP = ALPHA1
DN = 1.0 - ALPHA1
FLASHDUR = 100
LOGPRD = 2000
LOGLEVEL = 5
BOTSIZE = 100
BOTTYPE = :const
BOTCONSTSPEED = 10
BOTACTIVEFROM = 50 # a bot instance start after this
BOTACTIVERAND = 5 # a bot instance start sending packet from a random number between 0 and BOTACTIVERAND (will sum with BOTACTIVEFROM)
#---------- VARIABLES
$sc = Array.new # safe client
$rj = Array.new # Rejected trafic
$pr = Hash.new # Processing trafic
$botnet = nil
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
    	while @ind < @pkt.size && @pkt[@ind].timestamp_ >= time && @pkt[@ind].timestamp_ < time+PERIOD do
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
   def size
	return @pkt.size
   end
   def botMember? cid
      return @bots.map{|a,b| a}.include? cid
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
  def calcCorrel x,y
	sx = x.sum
	sy = y.sum
	sx2 = x.map{|n| n**2 }.sum
	sy2 = y.map{|n| n**2 }.sum
	sxy = x.zip(y).map{|a,b| a*b}.sum
	n = x.size
	c =  (n * sxy - sx * sy ) / (Math.sqrt((n*sx2 - sx**2 )*(n*sy2 - sy**2)))
	if c.nan? then c = 1 end
	return c
  end
  def method1
	@x = @pkt.values
	@y = @pkt.keys	
  end
  def method2
  	@x = @pkt.values.odd_values
	@y = @pkt.values.even_values
  end
  def process
     r =0
     if MTD == 1 then
     	method1
     else
     	method2
     end
     r = (calcCorrel @x,@y).abs
     @pkt.clear
     @p.push r
     @fst = @lst	
#
#     if r > UP || r < DN then
#	l 2,"traffic client #{@cid} is unpredictible in #{@p.size}'th time"
#     else
#	l 2,"traffic client #{@cid} is predictible in #{@p.size}'th time"
#     end
#
     if @p.size == K2 then
	pb = @p.sum / K2
	if (pb >= ALPHA2) then
		l 3,"traffic client #{@cid} is ATTACK by method #{MTD} pb=#{pb} -- #{($botnet.botmem @cid)?"BOTMEM":""}"
		makeAttack @cid
	else
		l 3,"traffic client #{@cid} is not ATTACK pb=#{pb} -- make safe -- #{($botnet.botmem @cid)?"BOTMEM":""}"
		makesafe @cid
	end
     end
  end
  def cleanup now
     if !@lst.nil? && (now - @lst > DLY) then
         l 3,"traffic client #{@cid} is safe due max delay -- #{($botnet.botmem @cid)?"BOTMEM":""}"
         makesafe @cid
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
  def get_x
	return @x
  end
  def get_y
	return @y
  end
  def get_pkt
	return @pkt
  end
  def get_p
	return @p
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
def b bind
        color_s = "\033[1m\033[31m"
        color_f = "\033[0m\033[22m"
        line= (caller.first.split ":")[1]
	vars = (eval('local_variables',bind) | eval('instance_variables',bind)).map{|v| "#{v.to_s}= #{eval(v.to_s,bind)}"}.join ";"
        puts  "#{color_s}#{Time.new.strftime("%H:%M:%S")} line:#{line} -- #{vars}#{color_f}"
	begin
		print "\033[31m"
	        begin
		  s = Readline.readline("dbg> ",true).strip
	          if s == "" then break end
	          eval ("puts ' = ' + (#{s}).to_s"),bind
		rescue => e
		  puts " > Error ocurred: \033[1m#{e.backtrace[0]}: #{e.message}\033[22m"
	        end while true
	ensure
		print "\033[0m"
	end
end
def x bind
        color_s = "\033[1m\033[33m"
        color_f = "\033[0m\033[22m"
        puts  "#{color_s}Execuation mode: #{color_f}"
        begin
                print "\033[33m"
                begin
                  s = Readline.readline("exe> ",true).strip
                  if s == "" then break end
                  eval ("puts ' = ' + (#{s}).to_s"),bind
                rescue => e
                  puts " > Error ocurred: \033[1m#{e.backtrace[0]}: #{e.message}\033[22m"
                end while true
        ensure
                print "\033[0m"
        end
end
def h_get hash_,key_
  return hash_[key_]
end 
$allowed = 0
def drop req
 $allowed+=1	
end
$denied =0
def allow req
 $denied+=1
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
$safes = 0
def makesafe cid
	$safes +=1
        $sc.push cid
        #$pr.delete cid
end
$attackers = 0
def makeAttack cid
	$attackers +=1
        $rj.push cid
        #$pr.delete cid
end
def cleanup time
	$pr.each_value{ |v| v.cleanup time }
end
$allPackets = 0
def simulate
	flash = FlashCrowd.new
	l 1,"Dataset #{DATASET} loaded for flash crowded traffic size=#{flash.size} TimeDuration=#{FLASHDUR} seconds"
	$botnet = BotNet.new(flash.maxCID+1 ,BOTSIZE,flash.stime,flash.etime)
	l 1,"BotNet simulator created with size=#{BOTSIZE} and startCID=#{flash.maxCID+1}"
	time = flash.stime
	while !flash.finished? do
		l 1,"Now= #{Time.at(time).strftime("%Y-%m-%d %H:%M:%S")} (#{time - flash.stime} seconds elapsed)"
	        fls = flash.nxt time
		bot = $botnet.nxt time
		time += PERIOD
		(fls | bot).each{ |req|
                        $allPackets +=1
			if $allPackets>0 && $allPackets % LOGPRD == 0 then l 1,"#{$allPackets} packets processed" end
			process req
		}
		if (time % DLY == 0) then
			cleanup time
		end
	end

	botnot = ((flash.maxCID+1)..(flash.maxCID+1+BOTSIZE)).select{|c| !$rj.include? c}.size
	flsyes = $rj.select{|c| c <= flash.maxCID}.size

	l 0, "Packets Analysied:\t\t\t #{$allPackets}"
	l 0, "Packets Allowed:\t\t\t #{$allowed}"
	l 0, "Packets Denied:\t\t\t #{$denied}"
	l 0, "Clients Analysied:\t\t\t #{$pr.size}"
	l 0, "Clients Determined Safe:\t\t #{$safes}"
	l 0, "Clients Determined Attacker:\t\t #{$attackers}"
	l 0, "Botnet clients not Detected:\t\t #{botnot}"
	l 0, "Dataset clients detected as attacker:\t #{flsyes}"
	x binding
end
#---------- InputArguments
MainBinding = binding
ARGV.each{|a|
        if a.strip == "dbg" then
                b  MainBinding
        end
}
#---------- MAIN
simulate
