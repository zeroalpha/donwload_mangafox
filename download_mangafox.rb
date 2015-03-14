require 'net/http'  
require 'fileutils' 
require 'thread'    

require 'nokogiri'

unless ARGV[0]
  puts "Usage : download_mangagox.rb <URL>"
  puts "Where <URL> is the full URL to the first page of the Manga"
  exit
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
      result = Net::HTTP.get(url)
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

threads = (1..number_of_pages).to_a.map do |num|
  Thread.new do
    page_url = base_url + num.to_s + '.html'
    picture_url = extract_picture_url page_url
    pic = download_picture picture_url
    filename = File.join(manga,volume,chapter,num.to_s + '.jpg')
    File.binwrite filename, pic
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
puts "\nDone !"