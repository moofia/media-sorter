# methods related to music
# at the moment nothing is done here

# call first for music to look and decide on what actions on will take with renaming or moving
def handle_music(music)
  return false if $config['music_file']['process'] != true
  log("handle_music -> do something with the music file #{music.file}")
  ap $config['music_file']['storage'] if $opt["debug"]
end

# check if the file is a movie file based on the file name
def music_file(file)
  ext_list = $config["music_file"]["media_extentions"].gsub(/,/,"|")
  
  ext = ".*\.(#{ext_list})$" 
  name = ""

  $config['music_file']['regex'].each do |pattern|
    if file =~ /.*#{pattern}#{ext}/i
      name    = $1 if $1
      return false if name =~ /^sample/i
      return true
    end
  end
  return false
end
