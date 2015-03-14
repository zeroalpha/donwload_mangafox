require 'net/http'  
require 'fileutils' 
require 'thread'    

require 'nokogiri'

require 'pry'

unless ARGV[0]
  puts "Usage : download_mangafox.rb <URL> [--all]"
  puts "Where <URL> is the full URL to the first page of the Manga"
  puts "--all is optional and trigers downloading the whole manga in one go, instead of the selected chapter"
  exit
end

if ARGV[1] == '--all' then
  ALL = true
else
  ALL = false
end

first_page_url = URI(ARGV[0])

path = first_page_url.path.split '/'

manga = path[2]
volume = path[3]
chapter = path[4]

base_url = first_page_url.path.gsub(/[^\/]*?\z/,"")
base_url = first_page_url.scheme + '://' + first_page_url.host + base_url

def repeat_get(url)
  url = URI(url)
  flag = true
  counter = 0
  while flag && counter < 5
    begin
      flag = false
      response = Net::HTTP.get_response(url)
      result = response.body
    rescue => e
      flag = true
      counter += 1
      puts url.inspect
      puts e.inspect
    end
  end
  raise "FUCK this : #{url}" if counter == 5
  result
end

def extract_picture_url(url)
  url = URI(url)
  html = repeat_get(url)
  doc = Nokogiri::HTML html
  pic_url = doc.css('#viewer > a > img')[0].attr("src")
end

def download_picture(url)
  url = URI(url)
  pic = repeat_get(url)
end

print "Fetching first page for #{manga} -> #{volume} -> #{chapter} ... "
html = repeat_get first_page_url
puts "Done"

print "Creating Directory Structure ... "
FileUtils.mkdir_p File.join(manga,volume,chapter)
puts "Done"

doc = Nokogiri::HTML html

number_of_pages = doc.css('div.r')[0].children[-4].children.last.content.strip.match(/\d+/)[0].to_i

puts "Starting to fetch #{number_of_pages} Pages"

@file_sizes = Queue.new
@download_log = Queue.new
#@average = 0
#@sizes = []
@downloads = []

average_keeper = Thread.new do
  #average = 0
  loop do
    #if @file_sizes.size > 0 then
    until @download_log.empty?
      #@sizes << @file_sizes.pop
      @downloads << @download_log.pop
      #total = @sizes.size
      #@average = @sizes.inject(0,:+).to_f./(total)
    end
    Thread.pass
    sleep 0.5
  end
end

threads = (1..number_of_pages).to_a.map do |num|
  Thread.new do
    page_url = base_url + num.to_s + '.html'
    picture_url = extract_picture_url page_url
    pic = download_picture picture_url
    filename = File.join(manga,volume,chapter,num.to_s + '.jpg')
    file_size = File.binwrite(filename, pic)
    #@file_sizes << file_size
    @download_log << {
      size: file_size,
      page_url: page_url,
      picture_url: picture_url,
      file_name: filename
      #picture: pic
    }
    pic
  end
end

thread_count = threads.size
loop do
  finished = threads.count{|t| !t.status}
  print "\rThreads finished : %03i / %i"%[finished,thread_count]
  break if finished == thread_count
  sleep 0.5
end

sleep 1
average_keeper.exit

sizes = @downloads.map{|d| d[:size]}
average = sizes.inject(0,:+).to_f / sizes.size
deviations = @downloads.map do |d|
  dev = 100 - (100.0/average * d[:size])
  d[:dev] = dev
  if dev > 45 then
    d[:repeat] = true
  end
  d
end

repeat_downloads = deviations.select{|d| d[:repeat]}
repeat_count = repeat_downloads.size
if repeat_count > 0 then
  counter = 0
  while repeat_count > 0 && counter < 5
    puts "Re-Downloading #{repeat_count} Downloads because of suspiciously low file sizes"
    repeat_downloads.map! do |d|
      pic = repeat_get d[:picture_url]
      d[:size] = File.binwrite d[:file_name],pic
      dev = 100 - (100.0/average * d[:size])
      d[:dev] = dev
      if dev > 45 then
        d[:repeat] = true
      else
        d[:repeat] = false
      end
      counter += 1
      d
    end
    repeat_count = repeat_downloads.select{|d| d[:repeat]}.size
  end  
  #binding.pry
end
#binding.pry
puts "\nDone !"