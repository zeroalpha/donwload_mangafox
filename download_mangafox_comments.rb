# Gems aus der Std-lib (müssen nicht mit 'gem install <GEM> installiert' werden)
require 'net/http'  # Für HTTP GET Requests
require 'fileutils' # Um ohne viel Aufwand verschachtelte Verzeichnisse anzulegen (manganame/volume/chapter)
require 'thread'    # Damit wir auf alle Bilder gleichzeitig warten können, statt nacheinander

# Nokogiri nimmt uns die grausame Arbeit ab HTML selbst parsen zu müssen
require 'nokogiri'

# ARGV ist ein Array, das alle, auf der Kommandozeile übergebenen, Parameter enthält
# ARGV[0] ist also der erste Parameter (die URL zur ersten seite eines Mangas)
# Wenn ARGV[0] nicht existiert, weil kein Parameter angegeben wurde
unless ARGV[0]
  # teilen wir das dem Benutzer mit
  puts "Usage : download_mangagox.rb <URL>"
  puts "Where <URL> is the full URL to the first page of the Manga"
  # Und beenden das ganze, damit er es nochmal versuchen kann
  exit
end

# Wenn wir hier sind gibt es ein ARGV[0]
# Und wir lassen uns von dem URI Modul ein URI:HTTP aus der URL Bauen
# URI = Uniform Resource Indentifiers
first_page_url = URI(ARGV[0])

# Hier passieren zwei Dinge
# 1. .path gibt uns alles, ab dem Hostteil.
#    Beispiel : URI('http://mangafox.me/manga/sherlock/v01/c003/1.html').path == '/manga/sherlock/v01/c003/1.html'
# 2. .split('/') splittet den string an jedem / und gibt uns ein array in der Form : ['','manga','sherlock','v01','c03','1.html']
#    Das Array, das von split zurückgegeben wird, speichern wir in der variablen path
path = first_page_url.path.split '/'

# Und hier weisen wir die teile des Array entsprechend bennanten variablen zu
# damit sich das keiner merken muss
manga = path[2]
volume = path[3]
chapter = path[4]

# Hier wird wieder mit .path der Path-Teil der URL genommen und dann wird alles ab dem letzen / durch nichts ersetzt (gelöscht)
# Beispiel : '/manga/sherlock/v01/c003/1.html'.gsub(/[^\/]*?\z/,"") == '/manga/sherlock/v01/c003/'
base_url = first_page_url.path.gsub(/[^\/]*?\z/,"")
# Und hier bauen wir mit dem abgeschnittenen pfad eine neue URL (nur als Text, hier machen wir noch kein URI Objekt)
base_url = first_page_url.scheme + '://' + first_page_url.host + base_url
# Als Ergebnis haben wir jetzt in base_url den Wert 'http://mangafox.me/manga/sherlock/v01/c003/'

# Die server von mangafox sind dermaßen langsam, dass so ein HTTP Request durchaus aus schiefgehen kann
# die methode repeat_get wiederholt einen HTTP Request bis zu fünf mal, bevor sie kapituliert und den stunk weitergeben (raise)
def repeat_get(url)
  # Hier wird aus der url wieder ein URI Objekt gemacht
  # Btw, das machen wir, weil man die (im gegensatz zu strings) direkt an Net::HTTP.get verfüttern kann
  url = URI(url)
  # flag und counter benutzen wir um zu entscheiden, wann wir die schleife verlassen
  flag = true
  counter = 0
  # Wir verlassen die schleife, wenn flag auf 'false' ist ODER der counter 5 erreicht hat, wenn ein schleifendurchlauf beendet wurde
  while flag && counter < 5
    # Wenn fehler auftreten, wirft ruby Exceptions, wenn man die nicht selbst behandelt, behandelt sie der Kernel und dessen Reaktion ist immer PAAAANIK und programm beenden
    # Mit begin .. rescue .. end können wir Exceptions fangen und selbst behandeln
    begin
      # Zuerst setzen wir die flag auf 'false', wenn alles beim HTTP.get gut geht, bleibt die auf false und wir verlassen die schleife
      flag = false
      # Hier wird der HTTP GET Request durchgeführt und das ergebnis in der variablen result gespeichert
      result = Net::HTTP.get(url)
    rescue => e
      # Wenn es eine Exception gab, wird dieser block ausgeführt und wir haben das Exception objekt in der Variablen e
      # Damit wir in der Schleife bleiben setzen wir flag wieder auf 'true'
      flag = true
      # Danach zählen wir den durchlaufzähler eins hoch
      counter += 1
      # Und geben der vollständigkeit halber die URL die zum Fehler geführt hat und den Fehler aus
      puts url.inspect
      puts e.inspect
    end
  end
  # Wenn die schleife verlassen wurde, weil der Zähler fünf erreicht hat raisen wir selbst eine Exception, damit der Kernel seine Panikatacke bekommt, weil dann ist irgendwas echt im argen
  raise "FUCK this : #{url}" if counter == 5
  # Wenn wir hier angekommen sind geben wir nur noch das ergebnis des HTTP Requests an die aufrufende stelle zurück
  # FYI: Ruby gibt IMMER was zurück, wenn nichts mit return 'abc' zurückgegeben wird, wird der letzte rückgabewert des blockes genommen

  result # ist das selbe wie 'return result' am ende der methode
end

# Ab hier wirds leichter, dass da oben war ja nur nötig, weil die mangafox server wirklich SO scheiße sind
# extract_picture_url lädt sie seite von Mangafox runter und pickt die URL für das JPG Bild, das wir haben wollen, da raus
def extract_picture_url(url)
  # Die URI Geschichte kommentiere ich ab hier nicht mehr ^^
  url = URI(url)
  # Wir holen den HTML inhalt mit unserer repeat_get funktion
  html = repeat_get(url)
  # Hier geben wir den HTML string an Nokogiri, und es gibt uns ein Document Objekt
  doc = Nokogiri::HTML html
  # Und von diesem Document Object können wir jetzt mit CSS-Selektoren einzelne HTML Elemente aus dem Dokument holen
  # der Selector '#viewer > a > img' selektiert alle <img> elemente, die Child-elemente von <a> elementen sind, die child-elemte von einem Element mit der id viewer sind
  # id: viewer, davon alle child elemente vom typ <a> und davon alle vom typ <img>
  # Wie der Selektor aussieht, hängt an der seite, mangafox ist da sehr schön strukturiert, so dass dieser selektor zuverlässig, das <img> element mit dem Scan vom Manga findet
  # Von diesem element gibt uns .attr jetzt den wert des 'src' attributes (dadrin steht die URL für das bild)
  # Nochmal zur errinerung, der Letzte rückgabewert wird als ergebnis der funktion zurückgegeben
  pic_url = doc.css('#viewer > a > img')[0].attr("src")
end

def download_picture(url)
  url = URI(url)
  # Hier wird das Bild runtergeladen und als Binär-String zurückgegeben
  pic = repeat_get(url)
end

# in Strings mit "" kann man mit #{} einfach Ruby code einfügen
# hier werden die werte der variablen mange, volume und chapter eingefügt
print "Fetching first page for #{manga} -> #{volume} -> #{chapter} ... "
# Dann laden wir die erste Seite runter um herauszufinden, wie viele Bilder das Kapitel enthält
html = repeat_get first_page_url
puts "Done"

print "Creating Directory Structure ... "
# Hier legen wir die Ordner für die Bilder an
# File.join setzt strings mit "/" oder "\" zusammen, damit wir nicht selbst entscheiden müssen, was richtig ist (windows/linux)
# und mkdir_p nimmt diesen string und legt im aktuellen verzeichnis eine entsprechende struktur an
FileUtils.mkdir_p File.join(manga,volume,chapter)
puts "Done"

# Wir Übergeben das HTML für die erste Seite an Nokogiri
doc = Nokogiri::HTML html

# Ähm ja
# Das müssen wir uns (wie den pic_selector auch) mal live auf der seite im HTML Code angucken
# rausgefunden hab ich die struktur stumpf über trial and error und rumgucken :D
number_of_pages = doc.css('div.r')[0].children[-4].children.last.content.strip.match(/\d+/)[0].to_i

puts "Starting to fetch #{number_of_pages} Pages"

# (1..number_of_pages).to_a baut uns ein Array mit den Zahlen von 1 - number_of_pages
# über dieses Array gehen wir mit map drüber und erstellen für jede seite ein Thread-Objekt zum runterladen
# und speichern das resultierende Array mit Thread-Objekten in der variablen threads
threads = (1..number_of_pages).to_a.map do |num| # num ist die schleifenvariable und enthält die aktuelle seiten-zahl
  # Thread new erstellt ein neues Thread-Objekt, das den Code in dem do..end Block ausführt
  Thread.new do
    # Wir bauen aus der base_url und der aktuellen zahl eine URL
    # Beispiel: 'http://mangafox.me/manga/sherlock/v01/c003/' + '1' + '.html'
    page_url = base_url + num.to_s + '.html'
    # Hier wird jetzt die in Zeile 84 definierte methode auch tatsächlich benutzt um die Bild-URL zu bekommen
    picture_url = extract_picture_url page_url
    # und dann wird das Bild runtergeladen und in der variablen pic gespeichert
    # FYI: Bilder sind auch nur Strings, ist halt kein Text drin sondern äh, knorz :D
    pic = download_picture picture_url
    # Hier bauen wir uns mit File.join einen Datei/Ordner namen
    filename = File.join(manga,volume,chapter,num.to_s + '.jpg')
    # Und schreiben mit binwrite (für binärstrings) das Bild in die Datei (binwrite musste ich auch erstmal lernen, File.write hatte nicht funktioniert ^^)
    File.binwrite filename, pic
    # Und geben das bild zurück (brauchen wir nicht, halte ich aber für guten Stil)
    pic
  end
end

# Das Tolle an Threads ist, dass sie parallel laufen, nachdem man einen Thread mit Thread.new erstellt hat, kann man mit Thread#join darauf warten, dass er fertig wird
# Hier war vorher diese schleife : 
#threads.each do |t|
#  print "."
#  t.join
#end
# Hier wird nacheinander auf jeden Thread gewartet, bis er fertig ist und sein bild auf die Platte geschrieben hat
# Aber als Fortschritts anzeige ist es unbrauchbar. Nehmen wir an, von 40 Bildern sind alle bis auf nummer 2 fertig,
# dann haben wir trotzdem erst zwei punkte ausgegeben und wenn zwei dann fertig ist, kommt INSTANT der rest der punkte

# Anzahl der Threads in eine variable speichern, damit wir nicht jeden schleifendurchlauf threads.size ausführen
thread_count = threads.size
# loop ist eine endlosschleife, sie hat keine schleifenbedingung wie while oder until sondern wird mit break verlassen
loop do
  # .count(){block} führt den block für jedes element des arrays aus und zählt wie oft der Block als rückgabewert true hatte
  # t.status ist entweder ein String, wenn er noch arbeitet oder wartet und nil oder false wenn er fertig ist
  # ! ist der verneinungsoperater !true == false
  # Da in Ruby ALLES ausser nil und false als true gilt gibt !t.status für arbeitende Threads false zurück und für fertige true
  # (ohne das ! wäre es grade andersrum)
  finished = threads.count{|t| !t.status}
  # \r bewegt den Cursor wieder an den anfang der zeile, so dass der vorherige text überschrieben wird
  # ausser mit #{} kann mann auch formatstrings benutzen um variablen in Strings einzufügen
  # hier werden zwei variablen eingefügt, finished und thread_count und zwar an den stellen mit den % im text
  # %03i bedeutet : Eine Ganzzahl (integer) wird auf drei stellen nach links mit nullen aufgefüllt
  # 1 wird also 001, 50 wird 050 und 300 bleibt 300 und 5000 bleibt 5000
  # %i bedeutet einfach nur ganzzahl ohne weitere formatierung
  print "\rThreads finished : %03i / %i"%[finished,thread_count]

  # Wenn die anzahl fertiges threads gleich der anzahl threads ist, sind alle threads fertig und wir können aus der schleife raus
  break if finished == thread_count
  # wenn nicht, warten wir ne halbe sekunde und gucken nochmal, wie viele fertig sind
  sleep 0.5
end
# YAY
puts "\nDone !"