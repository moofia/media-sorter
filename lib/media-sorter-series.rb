# all methods which will handle serieses

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

# wrapper method to decided which db to query
def series_lookup(episode)
  if $config.has_key? "tvdb" and $config["tvdb"].has_key? "api_key" and $config["tvdb"].has_key? "mirror"
    #log("series_lookup tvdb: #{episode.show}")
    thetvdb_lookup(episode.show)
  end
end
