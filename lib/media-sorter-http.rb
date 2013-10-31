# returns a xml of the url to get via a proxy
def http_get_via_proxy(url)
  log("http get via proxy : #{url}") if $opt["debug"]
  begin
    proxy = ENV['http_proxy']
    proxy_host, proxy_port = proxy.gsub(/^http:\/\//,'').split(/:/)
    myurl = URI.parse(url)
    req = Net::HTTP::Get.new(myurl.request_uri)
    res= Net::HTTP::Proxy(proxy_host, proxy_port).start(myurl.host,myurl.port) { |http| http.request(req) }
    html = res.body
  # XXX must fix the rescue its not working
  rescue => err
    log("Error: #{err}")
    exit 2
  end
  html
end

# returns a xml of the url to gets directly
def http_get_direct(url)
  log("http get : #{url}") if $opt["debug"]
  begin
    html = Net::HTTP.get_response(URI.parse(url)).body
  # XXX must fix the rescue its not working
  rescue => err
    log("Error: #{err}")
    exit 2
  end
  html
end

# handle http gets
def http_get(url)
  if ENV.has_key? "http_proxy"
    data = http_get_via_proxy(url)
  else
    data = http_get_direct(url)      
  end
  data
end
