# start of what is needed for json rpc for xbmc
# original idea taken from http://wiki.apache.org/couchdb/Getting_started_with_Ruby , that can be removed once 
# refactoring greater than 60%

module XBMC
  @log_base = "XBMC rpc:"
  class XBMCrpc
    def initialize(options = nil)
      @host = $config["http_rpc"]["host"]
      @port = $config["http_rpc"]["port"]
      @uri  = "/jsonrpc"
      @options = options
    end
  
    def get()
      requesting(Net::HTTP::Get.new(@uri))
    end
  
    def put(json)
      request = Net::HTTP::Put.new(@uri)
      request["content-type"] = "application/json"
      request.body = json
      requesting(request)
    end
  
    def post(json)
      request = Net::HTTP::Post.new(@uri)
      request["content-type"] = "application/json"
      request.body = json
      requesting(request)
    end
  
    def requesting(request)
      response = Net::HTTP.start(@host, @port) { |http|http.request(request) }
      unless response.kind_of?(Net::HTTPSuccess)
        handle_error(request, response)
      end
      response
    end
  
    private
  
    def handle_error(request, response)
      e = RuntimeError.new("#{response.code}:#{response.message}\nMETHOD:#{request.method}\nURI:#{request.path}\n#{response.body}")
      raise e
    end
  end
  
  # method to make the connection to the server and display the raw results
  def XBMC.rpc_action(method)
    log "#{@log_base} #{method}"
    json = <<-JSON
      {"jsonrpc":"2.0","method":"#{method}","id":1}
    JSON
    server = XBMCrpc.new
    response = server.post(json)
    result = JSON.parse(response.body)
    result
  end
  
  # list of methods for basic actions, at the moment making the full json object
  
  # play or pause
  def XBMC.play_pause
    rpc_action("VideoPlayer.PlayPause")
  end
  
  def XBMC.play
    rpc_action("XBMC.Play")
  end
  
  def XBMC.introspect
    rpc_action("JSONRPC.Introspect")
  end
  
  def XBMC.get_volume
    rpc_action("XBMC.GetVolume")
  end
  
  def XBMC.get_recently_added_episodes
    rpc_action("VideoLibrary.GetRecentlyAddedEpisodes")
  end
  
  def XBMC.scan_for_content
    rpc_action("VideoLibrary.Scan")
  end
  
  def XBMC.version
    rpc_action("JSONRPC.Version")
  end

  def XBMC.permission
    rpc_action("JSONRPC.Permission")
  end
  
  def XBMC.skip_next
    rpc_action("VideoPlayer.SkipNext")
  end




end
