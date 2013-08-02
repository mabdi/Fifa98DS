require 'bindata'

#----------- CONSTANTS
DATASET = "wc_day58_3"
PERIOD = 1 # period is 1 sec
K1 = 5 # MAX SIZE OF @pkt 
K2 = 5 # MAX SIZE OF @P
DLY = 15 # if a client is not request for a period of DLY its not a DDOS
ALPHA1 = 0.85
ALPHA2 = 0.95
UP = ALPHA1
DN = 1.0 - ALPHA1
FLASHDUR = 100
LOGPRD = 2000
LOGLEVEL = 5
BOTSIZE = 100
BOTCONSTSPEED = 1
BOTACTIVEFROM = 20 # a bot instance start after this
BOTACTIVERAND = 5 # a bot instance start sending packet from a random number between 0 and BOTACTIVERAND (will sum with BOTACTIVEFROM)
RED = "\033[31m"
YELLOW = "\033[33m"
BLUE = "\033[34m"
BOLD = "\033[1m"
BOLDEND = "\033[22m"
COLOREND = "\033[0m"
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

  def self.getNew time,cid
	ins = Worldcup98.new
	ins.timestamp_ = time
	ins.clientID_ = cid
	return ins
  end
end
class FlashCrowd
   def initialize
	@pkt = Array.new
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
	@stime = @pkt.first.timestamp_
	@etime = @pkt.last.timestamp_
   end
   def maxCID
	return @max
   end
   def size
	return @pkt.size
   end
   def stime
	return @stime
   end
   def etime
	return @etime
   end
   def nxt time
	return @pkt.select {|p| p.timestamp_ >= time && p.timestamp_ < time + PERIOD}
   end
end
class BotNet
   def  initialize startID,n,startTime,endTime
	@bots = (startID..(startID + n)).map{|x| [x, BOTACTIVEFROM + rand(BOTACTIVERAND).to_i]}
	const startTime,endTime
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
        return @pkt.select{|p| p.timestamp_ >= time && p.timestamp_ < time + PERIOD}
   end
end
class DSRequest
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
  def process
     r =0
     @x = @pkt.values
     @y = @pkt.keys
     r = (calcCorrel @x,@y).abs
     @pkt.delete 0
     @p.push r
     if @p.size == K2 then
	pb = @p.sum / K2
	if (pb >= ALPHA2) then
		l 3,"traffic client #{@cid} \tis ATTACK pb=#{pb} #{($botnet.botMember? @cid)?(set_red " -BOTMEM-"):""}"
		makeAttack @cid
	else
		l 3,"traffic client #{@cid} \tis not ATTACK pb=#{pb} -- make safe #{($botnet.botMember? @cid)?(set_red " -BOTMEM-"):""}"
		makesafe @cid
	end
     end
  end
  def cleanup now
     if ($sc.include? @cid) || ($rj.include? @cid) then 
	return 
     end
     if !@lst.nil? && (now - @lst > DLY) then
         l 3,"traffic client #{@cid} \tis safe due max delay #{($botnet.botMember? @cid)?(set_red " -BOTMEM-"):""}"
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
end
#---------- FUNCTIONS
def set_red s
	return "#{RED}#{s}#{COLOREND}"
end
def l(n,s)
   if n <= LOGLEVEL then
	color_s = "\033[1m\033[34m"
	color_f = "\033[0m\033[22m"
	space = "   " * n
	puts  "#{color_s}#{Time.new.strftime("%H:%M:%S")} #{space} #{s.to_s}#{color_f}"
   end
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
end
$attackers = 0
def makeAttack cid
	$attackers +=1
        $rj.push cid
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
	while time <= flash.etime do
		l 1,"Now= #{Time.at(time).strftime("%Y-%m-%d %H:%M:%S")} (#{time - flash.stime} seconds elapsed)"

	        fls = flash.nxt time
		bot = $botnet.nxt time 
		time += PERIOD
		(fls.concat bot).each{ |req|
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
end
#---------- MAIN
simulate
