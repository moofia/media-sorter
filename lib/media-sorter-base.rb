# start of an include file for all common methods

# yes or no prompt handling
def yes_no_prompt(msg)
  answer = ""
  while answer !~ /^y$|^n$/
    print "#{@script} -> #{msg} [y/n] ? "
    answer = STDIN.gets.chomp
  end
  return true if answer =~ /^y$/i
  false
end

# prompt new, based on actions to set some defaults
def handle_yes_no(action,msg)
  if action == "move_movie"
    if $config["settings"]["prompt_move_movie"]
      return yes_no_prompt(msg)
    else
      return true
    end
  end
  false
end

# prompt, based on action delete etc
def prompt(file,action,msg)
  if not $config["settings"]["prompt_prune_duplicates"]
    print msg
    answer = STDIN.gets.chomp
    if answer =~ /^y$/i
      FileUtils.rm(file,$options) if action == "delete"
    end
  elsif $config["settings"]["auto_prune_duplicates"]
    @script = File.basename $0 
    msg.gsub!(/#{@script} -> /,'')
    msg.gsub!(/remove new .*\[y\/n\]/,'autoremove occuring')
    msg.gsub!(/remove dup .*\[y\/n\]/,'autoremove occuring')
    log msg
    FileUtils.rm(file,$options) if action == "delete"
  end
end

# facilitate debugging of an object
def debug(d)
  ap d
  puts
  exit 2
end

# keep state of the errors so they can be displayed at the end
def handle_error(msg)
  @errors[msg] = true
end

# generic logger
def log(msg,level=nil)
 level ||= 1
 # this line seems odd to me, not too sure what it is trying to achieve or if its working.
 return if  level > $config["settings"]["log_level"]
 
 @script = File.basename($0).split(/\./)[0] 
 FileUtils.mkdir_p("#{$script_dir}/var/log") if not File.directory? "#{$script_dir}/var/log"
 
 logfile = $script_dir + "/var/log/#{@script}.log"
 logfile = $config["settings"]["log_directory"] + "/#{@script}.log" if $config["settings"].has_key? 'log_directory'
 if $config["settings"]["log_file"]
   File.open(logfile, 'a') do |f|
     now = Time.new.strftime("%Y-%m-%d %H:%M:%S")
     f.puts "#{@script} #{now} -> #{msg}"
   end
 end
 puts "#{@script} -> #{msg}"
end

# new logger just to keep track of new files, mostly used when not using xbmc
def log_new(msg)
 @script = File.basename($0).split(/\./)[0] 
 logfile = $script_dir + "/var/log/#{@script}_new.log"
 logfile = $config["settings"]["log_directory"] + "/#{@script}_new.log" if $config["settings"].has_key? 'log_directory'
 if $config["settings"]["log_file"]
   File.open(logfile, 'a') do |f|
     now = Time.new.strftime("%Y-%m-%d %H:%M:%S")
     f.puts "#{@script} #{now} -> #{msg}"
   end
 end
 puts "#{@script} -> #{msg}"
end

# check if the file is a tv file based on the file name
def tv_file(file)
  # FIXME: refactor!!!!
  ext_list = $config["series"]["media_extentions"].gsub(/,/,"|")
  
  ext = ".*\.(#{ext_list})$" 
  name, season, episode = "", "", ""
  $config['series']['regex'].each do |pattern|    
    if file =~ /#{pattern}#{ext}/i
      name    = $1 if $1
      season  = $2 if $2
      episode = $3 if $3
      episode = "#{$3}x#{$4}" if $3 and $4 =~ /^\d/      
      return true, name, season, episode
    end
  end
  return false, name, season, episode
end

# process movies to see what to do with it
def process_movie(src)
  return if @movie_dir !~ /\w/
  return if src =~ /\.nfo$/i
  return if src =~ /\/subs$/i
  return if src =~ /\.sample$/i
  if $config["movies_directory"]["process"] == true
    movie = Movie.new src    
    movie.status = handle_movie_directory movie if movie.is_movie?
  end
end

# handle unrar'n 
# this is only done for tv series if a single episode is found in the volume
def handle_rar(rar)
  if File.exists? rar
    log("handle_rar #{rar}") if $opt["debug"]
    directory = File.dirname(rar)
    ext_list = $config["series"]["media_extentions"].gsub(/,/,"|")
    
    episode_status, episode_name, episode_season, episode_episode = tv_file(File.basename(directory) + ".avi")
    if episode_status
      unrar_list = %x[unrar l #{rar}]
      count = 0
      unrar_list_file = ""
      #unrar_list.each do |line|
      unrar_list.split(/\n/).each do |line|
        if line =~ /(.*)(#{ext_list})\s+\d+\w\d+/
          count = count + 1
          unrar_list_file = line
        end
      unrar_list_file = "" if count > 1  
      end
      
      if unrar_list_file =~ /(.*)(#{ext_list})\s+\d+\w\d+/
        name = $1
        ext = $2
        if name =~ /\w+/ and ext =~ /#{ext_list}/
          target_file = name.gsub(/^\s+/,'') + ext
          media_file = directory + "/" + target_file
      
          episode_status, episode_name, episode_season, episode_episode = tv_file(target_file) if $config["series"]["process"] == true
          if episode_status and not File.exist? media_file
            command = "#{$config["settings"]["unrar_location"]} e #{rar} #{directory}"
            log("unrar #{target_file}")
            begin
              PTY.spawn(command) do |r, w, pid|
                begin
                  r.each do |line|
                  if line =~ /#{target_file}\s+(.*)/
                    puts $1
                  end
               end
               rescue Errno::EIO
               end
            end
            rescue PTY::ChildExited => e
              log("The child process exited!")
            end
            
            if File.exist? media_file
              if episode_status == true
                episode = Episode.new media_file
                if episode.is_ep?
                  episode.status = handle_series episode 
                  media = episode.class.to_s
                end
              end
            end
            
            FileUtils.rm_r(directory,$options)
          end
        end
      end   
    end
  end
end

# process file to see what to do with it or what the directory might be
def process_file(src)
  media = ""
  # files first
  get_files(src).each do |file|
    next if file =~ /\/\._/
        
    # first we check if the file is a tv series
    episode_status, episode_name, episode_season, episode_episode = tv_file(file) if $config["series"]["process"] == true
    if episode_status == true
      episode = Episode.new file
      if episode.is_ep?
        episode.status = handle_series episode 
        media = episode.class.to_s
      end
    end
    
    # second we check if the file is music
    music_status = music_file(file) if $config["music_file"]["process"] == true
    if music_status == true
      music = Music.new file
      if music.is_music?
        music.status = handle_music music 
        media = music.class.to_s
      end
    end
    
    # finally we can handle rar's
    handle_rar(file) if file =~ /\.rar$/ and file !~ /part\d+\.rar$/
    handle_rar(file) if file =~ /part01\.rar$/
    
  end # get_files
  media
end

# returns an array of tv files
def find_files(recusive,sort)
  ext_list = $config["series"]["media_extentions"].gsub(/,/,"|")
  files = []  
  if File.directory? sort
    Find.find(sort) do |path|
      next if File.dirname(path) != sort and not recusive
      next if File.directory? path
      next if File.basename(path) =~ /^\./
      next if path !~ /#{ext_list}$/
      files << path
    end
  else
    log("error: source directory of \"#{sort}\" does not exist!")
    exit 2
  end
  files
end

# returns an array of files that are not tv files
def find_files_not(sort)
  files = []
  Find.find(sort) do |path|
    next if File.directory? path
    next if File.basename(path) =~ /^\./
    next if (tv_file File.basename(path))
    files << path
  end
  files
end

# basic help
def help
  @script = File.basename $0 
puts <<HELP
  usage: #{@script} --src [src dir] --dst [destination dir] --debug

  --verbose                   verbose output
  --src                       source folder
  --dst                       destination folder
  --dst_no_hierarchy          destination folder hierarchy off
  --debug                     extra log messages for debugging
  --recursive                 recurse directory tree
  --tvdb                      correct filename based on tvdb
  --tvdb-refresh              force a refresh of tvdb content (warning applies globally)
  --dry                       dryrun, no files are renamed / removed
  --movie                     movie mode
  --dst_movie                 destination folder for movies
  --log-level                 log level
  --find-missing              find missing episodes. only finds missing episodes between min and max
  --prune-empty-directories   prune empty directories

  --help

  edit #{File.dirname($0)}/etc/media-sorter.yaml for more options
  
HELP

exit
end

# make sure there is enough free space on the dst
def ensure_free_space(src,dst)
  state = true
  #lines = %x[df #{dst}]
  #n = lines.last.split[1].to_i * 1024
  #debug lines
  return state
end

# moves the file to target location and creates directories if needed
def move_file(f,target)
  # do nothing if the file does not exist, this can occur
  return 2 if not File.exists? f
  log_new("move file -> #{File.basename(f) }")
  
  target_file = target + "/" + File.basename(f)   
  stats = {}
  stats["src_size"] = ( not File.size?(f).nil?) ? File.size?(f) : 0
  stats["dst_size"] = ( not File.size?(target_file).nil? ) ? File.size?(target_file) : 0
  
  if File.exists? f 
    if stats["src_size"] == 0 
      msg = "#{@script} -> src file zero bytes: \'#{File.basename(f) }\' remove new file ? [y/n] "
      prompt(f,"delete",msg)
      return 2
    end
    if stats["src_size"] < 100000000 and $config["settings"]["prune_small"] 
      msg = "#{@script} -> src file less than 100M: \'#{File.basename(f) }\' remove new file ? [y/n] "
      prompt(f,"delete", msg)
      return 2
    end

    if stats["dst_size"] == 0 and File.exists? target_file
      msg = "#{@script} -> dst file zero bytes will continue: \'#{File.basename(target_file) }\' remove new file ? [y/n] "
      prompt(target_file,"delete",msg)
    end
    if stats["dst_size"] < 100000000 and $config["settings"]["prune_small"] and File.exists? target_file
      msg = "#{@script} -> dst file less than 100M will continue: \'#{File.basename(target_file) }\' remove new file ? [y/n] "
      prompt(target_file,"delete", msg)
    end
  end
  
  $config["series"]["media_extentions"].split(/,/).each do |ext|
    file_target = File.basename(f).gsub(/.\w\w\w$/,'') + "." + ext
    if File.exists? "#{target}/#{file_target}"
      # choose which file to delete, we keep in order of the list
      order_target = 1
      order_new = 1
      count = 1
      $config["series"]["duplicate_priority"].split(/,/).each do |keep_ext|
        order_target = count if File.extname(file_target) =~ /#{keep_ext}/ 
        order_new = count if File.extname(f) =~ /#{keep_ext}/ 
        count = count + 1
      end
      delete_file = f
      delete_file = "#{target}/#{file_target}" if order_new < order_target
      if order_new != order_target
        msg = "#{@script} -> current file exist with another extention: \'#{File.basename(delete_file) }\' remove dup copy ? [y/n] "
        prompt(delete_file,"delete",msg)
        return 2
      end
    end
    
  end
  
  if File.exists? "#{target}/#{File.basename(f)}"
    log("warning dst file exists: \'#{File.basename(f)}\'",2) if $config["settings"]["log_level"] > 2
    if stats["src_size"] == stats["dst_size"] and $config["settings"]["prompt_prune_duplicates"] and f != target_file
      msg = "#{@script} -> duplicate equal size: \'#{File.basename(f) }\' remove new copy ? [y/n] "
      prompt(f,"delete",msg)
      return 2
    elsif stats["src_size"] != stats["dst_size"] and f != target_file
      msg = "duplicate: src \'#{f}\' (#{stats["src_size"]}) -> dst \'#{target_file}\' (#{stats["dst_size"]}) fix manually"
      #prompt(f,"delete",msg)
      log msg
    else
      log "warning src and dst equal for '#{File.basename(f)}\' with auto pruning enabled we choose to do nothing"
    end
    
    if $config["settings"]["log_level"] > 2
      if stats["src_size"] == stats["dst_size"]
        log "warning duplicate equal size: src \'#{f}\' -> dst \'#{target_file}\'"
        # should be safe to save some time here and prompt to ask if one wishes to remove src file
      else
        log "warning duplicate: src \'#{f}\' (#{stats["src_size"]}) -> dst \'#{target_file}\' (#{stats["dst_size"]})"
      end
    end
    return 2
  end
  
  is_space = ensure_free_space f, target
  
  if is_space 
    # if the directory does not exist it is created
    FileUtils.mkdir_p(target,$options) if not File.directory? target
    begin
    FileUtils.mv(f,target,$options) if ( (File.dirname f) != target.gsub(/\/$/,''))
    rescue => e
      log("error: problem with target, reason #{e.to_s}")
      exit 1
    end
    stats["dst_size"] = ( not File.size?(target_file).nil? ) ? File.size?(target_file) : 0
    if (stats["src_size"] != stats["dst_size"]) and not $opt["dry"]
      log("error target file not equal to original : \"#{File.basename(f)}\"")
    end

  else
    log("error not enough free space on \"#{target}\"")
    exit 2
  end
  
  1
end

# moves the directory to target location and creates directories if needed
def move_directory(directory,target)
 log_new("move directory -> #{File.basename(directory)}")
  
 if File.exists? "#{target}/#{File.basename(directory)}"
   log("warning dst directory exists: \'#{File.basename(directory)}\'")
 else 
   # if the directory does not exist it is created
   FileUtils.mkdir_p(target,$options) if not File.directory? target
   FileUtils.mv(directory,target,$options) if ( (File.dirname directory) != target.gsub(/\/$/,'')) 
 end
end

# call first for music to look and decide on what actions on will take with renaming or moving
def handle_music(music)
  return false if $config['music_file']['process'] != true
  log("handle_music -> do something with the music file #{music.file}")
  ap $config['music_file']['storage'] if $opt["debug"]
end

# call first to look and decide on renaming
def handle_series(episode)
  tvdb_result = series_lookup(episode) if ($opt["tvdb"]) && (! @tvdb_episodes.has_key?(episode.show))
  if tvdb_result == false
    handle_error("failed to find tvshow \'#{episode.show}\' from tvdb, skipping..") if $opt["debug"]
    return false
  end
  re_cache = episode.fix_via_tvdb @tvdb_episodes if $opt["tvdb"] and @tvdb_episodes.has_key?(episode.show)

  # we do one round of re-caching only if the episode name is not found
  if re_cache
    log("re-caching from tvdb")
    $opt["tvdb-refresh"] = true
    @tvdb_episodes = {}
    tvdb_result = series_lookup(episode) if ($opt["tvdb"]) && (! @tvdb_episodes.has_key?(episode.show))
    if tvdb_result == false
      handle_error("failed to find tvshow \'#{episode.show}\' from tvdb, skipping..")
      return false
    end
    episode.fix_via_tvdb @tvdb_episodes if $opt["tvdb"] and @tvdb_episodes.has_key?(episode.show)
  end
  
  # FIXME: temporay way to handle new destination folder
  target_directory_original = @tvdir
  if $show_storage.has_key? episode.show
    @tvdir = $show_storage[episode.show]
  end
  
  season_pre = "season."
  season_pre = $config["settings"]["season_dir_prepend"] if $config["settings"].has_key? "season_dir_prepend"
  season = "#{season_pre}#{episode.season}"
  season = "specials" if episode.season == "0"
  target = "#{@tvdir}/#{episode.show_on_fs}/#{season}"  
  target = "#{@tvdir}" if $opt["dst_no_hierarchy"]

  move_file(episode.original_file,target)
  @tvdir = target_directory_original
end

def find_missing(files) 

  eps = {}

  season_pre = "season."
  season_pre = $config["settings"]["season_dir_prepend"] if $config["settings"].has_key? "season_dir_prepend"
  # loop through list of files looking for media
  files.each do |file|
    next if not file[/.*\/(.*)\/#{season_pre}.*\/.*\s\[(\d+)x(\d+)\]\s(.*)/i]
    show = $1
    season = $2
    number = $3.to_i.to_s
    eps[show]                 = {} if eps[show].class.to_s != 'Hash'
    eps[show][season]         = {} if eps[show][season].class.to_s != 'Hash'
    eps[show][season][number] = file

    # this is a complete mess!!
    # tons of bugs, must fix
    # refactor!
    
    if ($config["tvdb"]["tvdb_find_missing"]) and ! eps[show].has_key? "tvdb_find_missing"
      tvdb_result = tvdb(show)
      
      if tvdb_result == false 
        handle_error("failed to find tvshow \'#{show}\' from tvdb, skipping..")
      else
        max = @tvdb_episodes[show][season].max[0]
        tmp_date = "2020-01-01"
        @tvdb_episodes[show][season][max].keys.each do |name|
          tmp_date = @tvdb_episodes[show][season][max][name]["first_aired"] if @tvdb_episodes[show][season][max][name].has_key? "first_aired"
          end
debug "forced exit, refactor first"
        yyyy, mm, dd = $1, $2, $3 if tmp_date =~ /(\d+)-(\d+)-(\d+)/
        if Time.mktime(yyyy, mm, dd) < Time.now.localtime
          eps[show]["tvdb_find_missing"] = Hash.new unless eps[show]["tvdb_find_missing"].class == Hash
          eps[show]["tvdb_find_missing"][season] = Hash.new unless eps[show]["tvdb_find_missing"][season].class == Hash
          eps[show]["tvdb_find_missing"][season]["max"] = max
        end
      end
    end
  end

  eps.keys.each do |show|
    eps[show].keys.each do |season|
      next if season == "tvdb_find_missing"
      max = eps[show][season].max_by{|k,v| v}[0].to_i

      if eps[show].has_key? "tvdb_find_missing"
        max = eps[show]["tvdb"][season]["max"] if eps[show]["tvdb"].has_key? season
      end

      1.upto(max) do |i|
        # found a missing episode, for now just display something
        log("missing: #{show} season #{season} -> number #{i}") if not eps[show][season].has_key? i.to_s
        end
      end
    end    

end

# when trying to remove directories there are varies odd dot files that can be 
# removed and other annyonging files
def remove_arb_dot_files(src)
  dot_files = Array.new
  dot_files << "DS_Store"
  dot_files << "_.DS_Store"
  dot_files << "com.apple.timemachine.supported"
  dot_files << "Thumbs.db"
  
  dot_files.each do |file|
    dot_file_remove = "#{src}/.#{file}"
    FileUtils.rm(dot_file_remove,$options) if File.exists? dot_file_remove
  end

  # handle removing of temp macos ._ files
  Find.find(src) do |path|
    next if File.basename(path) !~ /^\._/
    dot_file_remove = "#{src}/#{File.basename(path)}"
    FileUtils.rm(dot_file_remove,$options) if File.exists? dot_file_remove
  end

end

# clean up unwanted files that get in the way based on extension
def clean_arb_dot_files(src)
  clean_list = $config["clean"]["remove_extentions"].split(/,/)

  Find.find(src) do |path|
    next if File.basename(path) =~ /^\._/
    clean_list.each do |ext|
      next if path !~ /\.#{ext}/
      FileUtils.rm(path,$options) if File.exists? path
    end

  end
end

# clean up unwanted files that get in the way based on name
def clean_arb_named_files(src)
  clean_list = $config["clean"]["remove_named"].split(/,/)

  Find.find(src) do |path|
    next if File.basename(path) =~ /^\._/
    clean_list.each do |name|
      next if path !~ /#{name}\./
      FileUtils.rm(path,$options) if File.exists? path
    end

  end
end

# returns a list of files
def get_files(src)
  files = Array.new
  if File.directory? src
    Find.find(src) do |path|
      next if File.directory? path
      files.push path
    end
  else
    log("error: source directory of \"#{src}\" does not exist!")
    exit 2
  end
  files.reverse
end

# returns a list of directories
def get_directories(src)
  directories = Array.new
  #return directories
  Find.find(src) do |path|
    # not too sure what this was intended to do but its getting in the way
    # and can not be matched correctly.
    #next if File.dirname(path) != src 
    next if path == src
    next if not File.directory? path
    directories.push path
  end
  directories.reverse
end

# removes empty directories
def remove_empty_directories(src)
  found = false
  get_directories(src).each do |dir|
    tmp_dir = dir.gsub(/\[/,'\[')
    tmp_dir.gsub!(/\]/,'\]')

    clean_arb_dot_files(dir) if $config["clean"]["process"] == true
    clean_arb_named_files(dir) if $config["clean"]["process"] == true

    if Dir["#{tmp_dir}/*"].empty?
      log("cleanining up : #{src}") if not found
      
      log("removing empty directory : #{dir}")
      remove_arb_dot_files(dir)
      FileUtils.rmdir(dir,$options)
      found = true
    end 
  end

  get_directories(src).each do |dir|
    if not Dir["#{dir}/*"].empty? and $config["settings"]["log_level"] > 1
      log("unable to remove, directory not empty: #{dir}") 
    end
  end
  
  log("no empty directories were found") if not found and $opt["prune-empty-directories"]
end

# list of shows stored on storage device
def shows_on_storage_device(path,src)
  shows = {}
  src.each do |s|
    show = s.gsub(/#{path}/,'')
    show = "/#{show}" if show !~ /^\//
    show = File.dirname(show).split(/\//)[1]
    shows[show] = true if show =~ /\w/
  end
  shows
end

# check if the file is a movie file based on the directory name
def movie_directory(directory)

  movie = ""
  $config['movies_directory']['regex'].each do |pattern|
    if directory =~ /#{pattern}/i
      movie   = $1 if $1
      return true, movie
    end
  end
  return false, movie
end

# check if the file is a movie file based on the file name
def movie_file(file)
  ext_list = $config["movies_file"]["media_extentions"].gsub(/,/,"|")
  ext = ".*\.(#{ext_list})$" 
  name = ""

  $config['movies_file']['regex'].each do |pattern|
    if file =~ /.*#{pattern}#{ext}/i
      name    = $1 if $1
      return false if name =~ /^sample/i
      return true
    end
  end
  return false
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

# based on what the object is enrich the object
def enrich_object(object)
  movie_lookup(object) if object.class.to_s == "Movie" and $config["themoviedb"]["default"] == true
end

# wrapper method to decided which db to query
def movie_lookup(movie)
  if $config.has_key? "themoviedb" and $config["themoviedb"].has_key? "api_key" and $config["themoviedb"].has_key? "base_url"
    log("movie_lookup themoviedb: #{movie.name}") if $opt["debug"]
    themoviedb_lookup movie
  end
end

# wrapper method to decided which db to query
def series_lookup(episode)
  if $config.has_key? "tvdb" and $config["tvdb"].has_key? "api_key" and $config["tvdb"].has_key? "mirror"
    #log("series_lookup tvdb: #{episode.show}")
    thetvdb_lookup(episode.show)
  end
end

# handle the movie directory and decided what actions must be taken
def handle_movie_directory(movie)  
  log("handle_movie_directory: #{movie.directory}") if $opt["debug"]
  files = find_files(false,movie.directory)
  status = true
  files.each do |file|
    # we must first make sure its not a tv file
    tv_status, tv_show, tv_season, tv_number  = tv_file File.basename file
    if tv_status
      log ("error: #{movie.directory} contains a tv show -> #{File.basename file}")
      status = false 
    end
    if not tv_status
      # for now we only interested in if anything matches, later we can remove non movie
      # related files if we wish
      status = movie_file File.basename file if status == true
    end
  end

  if status == true
    movie.enrich
    # hmmm not too sure about this ?
    if $config["themoviedb"].has_key? "display_info_move" and $config["themoviedb"]["display_info_move"] == true
      themoviedb_display movie 
      result = handle_yes_no("move_movie","keep \"#{movie.name}\" based on the description ")
    end
    result = handle_yes_no("move_movie","movie found: move #{movie.title_full} \"#{movie.name}\"")
    if result
      move_directory(movie.directory,@movie_dir) 
    end
  else
    log("move #{movie.directory} -> contains invalid files doing nothing")    
  end
    
  status
end

# test if unrar exists
def unrar_found_test
  unrar = %x[which unrar].chomp
  if unrar =~ /\w/
    $config["settings"]["unrar_location"] = unrar
    log("unrar_found_test (#{$config["settings"]["unrar_location"]})") if $opt["debug"]
  end
end

# test if the filesystem is case sensitive or not
def fs_case_sensitivity_test
  dirs = []
  dirs << @movie_dir if @movie_dir
  dirs << @tvdir if @tvdir
  dirs.each do |dst|
  test_directory = "#{dst}/#{$$}"
    if File.directory? dst
      if not File.directory? test_directory
        $options_fs = {}
        #$options_fs = {:noop=>true,:verbose=> true} if $opt["dry"]
        $options_fs = {:noop=>true} if $opt["dry"]
        
        FileUtils.mkdir_p(test_directory,$options_fs)       
        file1 = "#{test_directory}/file"
        file2 = "#{test_directory}/FILE"
        FileUtils.touch(file1,$options_fs)
        FileUtils.touch(file2,$options_fs)
        
        count = 0
        
        if File.exist? test_directory
          Find.find(test_directory) do |file| 
            next if  FileTest.directory?(file)
            count = count + 1
          end
          
          FileUtils.rm(file1,$options_fs)
          FileUtils.rm(file2,$options_fs) if count == 2
          FileUtils.rmdir(test_directory,$options_fs)
          
          $config["settings"]["fs_case_sensitive"] = true if count == 2
          $config["settings"]["fs_case_sensitive"] = false if count == 1      
          log("fs_case_sensitivity_test on #{dst} (#{$config["settings"]["fs_case_sensitive"]})") if $opt["debug"]
        end
      end
    end  
  end
end

# test if the filesystem is case sensitive or not
def new_fs_case_sensitivity_test (directory)
  if File.directory? dst
    if not File.directory? test_directory
      $options_fs = {}
      #$options_fs = {:noop=>true,:verbose=> true} if $opt["dry"]
      $options_fs = {:noop=>true} if $opt["dry"]
      
      FileUtils.mkdir_p(test_directory,$options_fs)       
      file1 = "#{test_directory}/file"
      file2 = "#{test_directory}/FILE"
      FileUtils.touch(file1,$options_fs)
      FileUtils.touch(file2,$options_fs)
      
      count = 0
      Find.find(test_directory) do |file|
        next if  FileTest.directory?(file)
        count = count + 1
      end
      
      FileUtils.rm(file1,$options_fs)
      FileUtils.rm(file2,$options_fs) if count == 2
      FileUtils.rmdir(test_directory,$options_fs)
  
      $config["settings"]["fs_case_sensitive"] = true if count == 2
      $config["settings"]["fs_case_sensitive"] = false if count == 1      
      log("fs_case_sensitivity_test on #{dst} (#{$config["settings"]["fs_case_sensitive"]})") if $opt["debug"]
      
    end
  end  
end

def display_errors
  puts
  # see which media files were found but failed to an episode that we expected 
  @new_movie = false
  Movie.find_all.each do |m|
    log("error: not a recognized movie #{m.directory}") if not m.is_movie? if File.exists? m.directory
    @new_movie = true if m.is_movie?
  end
  # show errors
  puts

  @errors.keys.each do |e|
    log(e)
  end

  # see which media files were found but failed to an episode that we expected 
  @new_media = false
  directories = {}
  Episode.find_all.each do |e|
    if not e.is_ep?
      log("error: not a recognized episode #{e.file}") 
      directories[File.dirname e.file] = true
    end
    @new_media = true if e.is_ep?
  end

  if directories.count > 1 and @movie_dir =~ /\w/
    log("directories found that are not a tv series, movie_dir is set , checking for movies") 
    directories.keys.each do |directory|
      movie = Movie.new directory    
      movie.status = handle_movie_directory movie if movie.is_movie?
    end
  end

end

def correct_name

  episode_status, episode_name, episode_season, episode_episode = tv_file("#{$opt["correct-name"]} foo.avi")
  if episode_status == true
    episode = Episode.new $opt["correct-name"]
    if episode.is_ep?
      episode.season.gsub!(/^/,'0') if episode.season.to_i < 10 and episode.season.to_i != 0
      episode.number.gsub!(/^/,'0') if episode.number.to_i < 10 and episode.number.to_i != 0
      print "#{episode.show} #{episode.season} #{episode.number}"
    end
  end
end

# find where a show is stored physically on disk
def find_storage_locations
  if setting_ok_storage_locations
    $config["settings"]["storage destinations"]["tv"].each do |directory|
      files_secondary = find_files(true,directory)  
      shows_on_storage_device(directory,files_secondary).keys.each do |show|
        $show_storage[show] = directory
      end
    end
  end
end

# check the setting for the directories and make sure they are valid and 
# remove any directories that are invalid
# only works for tv right now
def setting_ok_storage_locations
  status = false
  new_storage = []
  
  if $config.has_key? "settings"
    if $config["settings"].has_key? "storage destinations"
      if $config["settings"]["storage destinations"].has_key? "tv"
        if $config["settings"]["storage destinations"]["tv"].class == Array
          $config["settings"]["storage destinations"]["tv"].push $opt["dst"] if $opt.has_key? "dst"
          $config["settings"]["storage destinations"]["tv"].uniq!
          $config["settings"]["storage destinations"]["tv"].each do |directory|
            if  File.directory? directory
              new_storage << directory
            end
          end
          status = true
        end
      end
    end
  end
  $config["settings"]["storage destinations"]["tv"] = new_storage
  if $config["settings"]["storage destinations"]["tv"].count == 0
    log "error: no storage destinations configured!"
    exit
  end
  return status
end
