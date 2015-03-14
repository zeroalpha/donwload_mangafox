require 'fileutils'

manga_name = 'sherlock'
dir_name = manga_name + "-continuous"

puts "Merging #{manga_name}"

entries = Dir.glob manga_name + '/**/**'
files = entries.select{|e| File.file?(e)}

puts "Copying #{files.size} Files"

Dir.mkdir(dir_name) unless Dir.exists?(dir_name)

files_count = files.size
files.each_with_index do |file,i|
  new_name = file.split('/').join('-')
  new_name = File.join dir_name,new_name
  FileUtils.cp file,new_name
  print "\rCopied #{i+1}/#{files_count}"
end
puts "\nDone"