require 'net/http'  
require 'fileutils' 
require 'thread'    

require 'nokogiri'

require 'pry'

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
  raise "FUCK this : #{url.inspect}" if counter == 5
  result
end

def extract_picture_url(url)
  url = URI(url)
  html = repeat_get(url)
  doc = Nokogiri::HTML html
  pic_url = doc.css('#viewer > a > img')[0].attr("src")
end

# Riesieger haufen Textverarbeitungswahnsinn, ich kommentiere nur grob was passiert, wie man da hinkommt machen wir dann live
def extract_chapter_list(url)
  url = URI(url)
  manga_name = url.path.split('/')[2]

  # Holen der Seite und übergabe an Nokogiri
  html = repeat_get(url)
  doc = Nokogiri::HTML html
  # Wir holen uns das vorletzte Javascript Tag aus dem Dokument
  # Warum ein Javascript tag ? Weil mangafox (warum auch immer) das Dropdown-Menü in dem man das Kapitel wählen kann erst NACH aufbau der der Seite per Javascript mit inhalt füllt
  # Ergo müssen wir uns jetzt den javascript code angucken und zerpflücken um an die Liste zu kommen
  script_tag = doc.css('script')[-2]
  # Stumpfes nachschauen im Netzwerkverkehr (Google Developer Tools) zeigt nur einen lokalen JS (AJAX) Request: /media/js/list.11428.js?1611426063382
  # wir holen also aus den queueScript dingern das raus, dass irgendwo 'media/js/list' enthält
  queued_scripts = script_tag.content.scan(/\.queueScript\(\"(.*?)\"\)/).flatten
  media_ls = queued_scripts.select{|s| s.index("media/js/list")}.first

  # Dann kleben wir uns mit dem gefundenen Pfad und unserem host (mangafox.me) und scheme (http) eine URL zurecht über die wir den Javascript mit dem Inhalt der Liste bekommen
  list_request = url.scheme + '://' + url.host + media_ls
  # Wir holen den Javascript der die Liste in die Seite einbaut
  javascript = repeat_get list_request
  # Textverarbeitung YAY RegExp YAY #map YAY wie gesagt, klären wir live
  js_array = javascript.match(/var chapter_list = new Array\((.*?)\);/m)[1]
  entries = js_array.scan(/\[(.*?)\]/).flatten.map{|e| e.split(',').last}
  urls = entries.map{|e| e.match(/\"(.*?)\"/)[1]}
  # Relevant ist : am ende bauen wir eine Liste mit kompletten URLs für jedes kapitel
  urls.map{|u| url.scheme + '://' + url.host + '/manga/' + manga_name + '/' + u + '/1.html'}
end

def download_picture(url)
  url = URI(url)
  pic = repeat_get(url)
end

def download_chapter(url)
  url = URI(url)
  base_url = url.path.gsub(/[^\/]*?\z/,"")
  base_url = url.scheme + '://' + url.host + base_url
  path = url.path.split '/'

  manga = path[2]
  volume = path[3]
  chapter = path[4]

  puts "Downloading #{url}"
  print "Fetching first page for #{manga} -> #{volume} -> #{chapter} ... "
  html = repeat_get url
  puts "Done"

  print "Creating Directory Structure ... "
  FileUtils.mkdir_p File.join(manga,volume,chapter)
  puts "Done"

  doc = Nokogiri::HTML html
  number_of_pages = doc.css('div.r')[0].children[-4].children.last.content.strip.match(/\d+/)[0].to_i

  puts "Starting to fetch #{number_of_pages} Pages"

  # Das hier ist neu. Wir versuchen kurz uns daran zu errinern, dass wir das ganze nur machen, damit viele Threads parallell (kp wieviele ls da reinmüssen) auf mangafox warten können
  # Das problem bei der pralalellität von Threads liegt in der Zugriff auf Variablen. Wenn zwei Threads gleichzeitig auf die selbe Variable zugreifen (schreibend) können sie den Wert da drin 
  # völlig ruinieren. Wir müssen aber daten über die jeweiligen Downloads aus den Threads herausbekommen um die zu sammeln und nachher auf zu kleine Dateien (miese qualität) zu prüfen.
  # Dafür gibt es Queues, wenn mehrere Threads mit Queue.push (Queue << ) oder Queue.pop auf die Queue zugreifen, sorgt diese zuverlässig dafür, dass deren interaktionen NACHEINANDER erledigt werden.
  @download_log = Queue.new
  # Ein leeres Array in dem am Ende die download-daten landen
  @downloads = []

  # Hier ist ein Thread, dessen einzige aufgabe es ist, die Download Daten aus der @download_log queue in das @downloads array zu schieben 
  downloads_collector_thread = Thread.new do
    loop do
      # Wenn daten in der queue sind
      until @download_log.empty?
        # Holt er einen datensatz aus der queue und schreibt ihn nach @downloads
        @downloads << @download_log.pop
      end
      # Wir teilen dem Thread Scheduler mit, dass er nen anderen Thread in den Vordergrund holen kann, weil wir jetzt erstmal nix tun
      Thread.pass
      # und tun dann wirklich erstmal ne halbe sekunde nix
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
      # Auf die @download_log Queue wird ein Datensatz mit den eckdaten des downloads geschoben
      @download_log << {
        size: file_size,
        page_url: page_url,
        picture_url: picture_url,
        file_name: filename
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

  # Wir warten noch ne sekunde, damit der collector_thread auf jedenfall genug zeit hatte, alle nachrichten zu holen und nach @downloads zu schieben
  sleep 1
  # und dann massakrieren wir ihn hinterrücks.
  downloads_collector_thread.exit

  # Wir machen ein Array, dass nur aus den size angaben der datensätze besteht
  sizes = @downloads.map{|d| d[:size]}
  # Berechnen den durchschnitt (inject klären wir auch live ^^)
  average = sizes.inject(0,:+).to_f / sizes.size
  # HAHA Statistik Sieg über miese Bilder :D
  # Wir berechnen für jeden Download, wie weit seine Größe in Prozent vom Durchschnitt abweicht :D
  deviations = @downloads.map do |d|
    dev = 100 - (100.0/average * d[:size])
    # Wir fügen die berechnete deviation dem download datensatz hinzu
    d[:dev] = dev
    # Und wenn die abweichung größer als 45% ist markieren wir den Download zum wiederholen
    if dev > 45 then
      d[:repeat] = true
    end
    d
  end

  # Wir speichern alle downloads die mit repeat = true markiert sind in ein neues array repeat_downloads
  repeat_downloads = deviations.select{|d| d[:repeat]}
  repeat_count = repeat_downloads.size

  # Wenn das nicht leer ist
  unless repeat_count.empty? then
    counter = 0
    # Wir versuchen wieder bis zu 5 mal mangafoxes jämmerlichkeit auszugleichen
    # Oder bis alle bilder in tragbarer qualität da sind 
    while repeat_count > 0 && counter < 5
      puts "Re-Downloading #{repeat_count} Downloads because of suspiciously low file sizes"
      repeat_downloads.map! do |d|
        # Da wir die bild URL gespeichert haben, brauchen wir nur nochmal repeat_get aufzurufen
        pic = repeat_get d[:picture_url]
        # Das Bild nochmal speichern
        d[:size] = File.binwrite d[:file_name],pic
        # und mit der neuen größe die abweichung berechnen
        dev = 100 - (100.0/average * d[:size])
        d[:dev] = dev
        # neue markierung setzen
        if dev > 45 then
          d[:repeat] = true
        else
          d[:repeat] = false
        end
        # zähler erhöhen
        counter += 1
        d
      end
      # zählen, wieviele noch markiert sind
      repeat_count = repeat_downloads.select{|d| d[:repeat]}.size
    end  
  end
  puts "\nDone !"
end

###########################
##                       ##
## ENDE DER DEFINITIONEN ##
## (Anfang der Aktion)   ##
##                       ##
###########################

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

if ALL then
  chapter_list = extract_chapter_list ARGV[0]
  chapter_list.each_with_index do |url,i|
    puts "Donwloading Chapter #{i + 1}/#{chapter_list.size}"
    download_chapter url
  end
else
  download_chapter ARGV[0]
end