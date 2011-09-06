# start of an include file for all classes

# Episode class
class Episode
  attr_reader :file, :number, :name, :season, :show, :original_file, :series_name, :show_on_fs
  attr_accessor :file
  attr_writer :show, :status, :series_name
  
  # initialize the object with some basic settings
  def initialize(file)
    @file = file
    @original_file = file
    @status, @show, @season, @number, @name, @series_name = false, "", "", "", "", ""
    @status, show, @season, @number  = tv_file File.basename file
    @season.gsub!(/^s/i,'')
    @season.gsub!(/^0/,'') if @season != "0"    
    @number.gsub!(/^0/,'') if @number != "0"
    
    @show = show_name_rename show
    @series_name = @show
    
    #@number.gsub!(/^/,'0') if @number.to_i < 10 and @number.to_i != 0
  end
  
  # return the status if the episode matches our expected syntax
  def is_ep?
    @status
  end
  
  # tv show name
  #def show
  #  @show.gsub!(/\./,' ')
  #  $config["rename"]["show"].keys.each {|s| @show.gsub!(/^#{Regexp.escape(s)}$/i,$config["rename"]["show"][s])}
  #  @show.gsub!(/(\s|\.)(\d\d\d\d)$/,'(\2)')
  #  @show = @show.titlecase
  #end
  
  # renames the file name based on tvdb and other local criteria when writing to a filesystem.
  def fix_via_tvdb(episodes)
    success = true
    log("attempting to fix name based on tvdb") if $opt["debug"]
    @name = episodes[@show][@season][@number] if episodes[@show][@season]
    ap episodes[@show] if $config["settings"]["log_level"] > 3 
    if not @name.nil?
      success = false
      @name = CGI.unescapeHTML(@name)
      @name.gsub!(/\//,'-')
      @name.gsub!(/\?/,'')
      @name.gsub!(/\:/,' ')
      @name.gsub!(/\s+$/,'')    
      @show.gsub!(/\:/,'')
      @number.gsub!(/^/,'0') if @number.to_i < 10 and @number.to_i != 0

      @name = "#{@show_on_fs} [#{@season}x#{@number}] #{@name}" 
      @name.gsub!(/\s\s/,' ') 
      orig = @original_file
      @file = File.dirname(orig) + "/" + @name + File.extname(File.basename(orig))

      #FileUtils.mv(orig,@file,$options) if orig.downcase != @file.downcase
      if orig != @file and $config["settings"]["fs_case_sensitive"] == true
        log "fix_via_tvdb: #{orig} to #{@file}"        
        FileUtils.mv(orig,@file,$options) 
        @original_file = @file
      elsif orig.downcase != @file.downcase
        log "fix_via_tvdb: #{orig} to #{@file}"
        FileUtils.mv(orig,@file,$options) 
        @original_file = @file
      end
    end
    success
  end
  
  # returns all Episode class's
  def self.find_all
    ObjectSpace.each_object(Episode)
  end
  
  :private
  def show_name_rename(show)
    show.gsub!(/\./,' ')    
    show.gsub!(/\s+$/,'')    
    $config_rename["rename"]["show"].keys.each {|s| show.gsub!(/^#{Regexp.escape(s)}$/i,$config_rename["rename"]["show"][s])}    
    show.gsub!(/(\s|\.)(\d\d\d\d)$/,' (\2)')
    show = show.downcase.titlecase
    @show_on_fs = show.gsub(/\*/,'')
    show
  end
end
