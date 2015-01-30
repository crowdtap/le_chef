require 'net/http'
require 'json'

class LogentriesAPI
  def initialize(account_key)
    @account_key = account_key

    @get_uri_base = 'http://api.logentries.com/' + @account_key
    @post_uri = URI('http://api.logentries.com')
    @datahub_uri = URI('https://logentries.com/hoover/api/new-connection/')
  end

  def self.default_pattern(host, log)
    host + '.*' + log
  end

  def create_datahub_mapping(host, log, pattern=nil, name=nil)
    pattern ||= default_pattern(host, log)
    name ||= host + ' ' + log

    create_host(host) unless hosts.has_key? host
    create_log(host, log) unless hosts_logs[host].has_key? log

    request = {
      'name' => name,
      'pattern' => pattern,
      'account_key'=> @account_key,
      'token' => hosts_logs[host][log],
      'source_tag' => '',
      'source_host' => ''
    }

    uri = @datahub_uri
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl=true
    http.post(uri.path, request.to_json)
  end

  def create_host(host)
    request = {
      'request' => 'register',
      'user_key'=> @account_key,
      'name'=> host,
      'distver' => '',
      'system' => '',
      'distname' => ''
    }

    hosts[host] = post_json(request)['host_key']
  end

  def create_log(host, log)
    request = {
      'request' => 'new_log',
      'user_key'=> @account_key,
      'host_key' => hosts[host],
      'name' => log,
      'type' => '',
      'retention' => '-1',
      'source' => 'token'
    }

    @hosts_logs[host][log] = post_json(request)['log']['token']
  end

  def delete_host(host)
    return unless hosts.has_key? host

    request = {
      'request' =>'rm_host',
      'user_key'=> @account_key,
      'host_key'=> hosts[host]
    }

    r = post_json(request)

    @hosts.delete(host)
    @hosts_logs.delete(host)
    r
  end

  # returns a mapping (host name)
  def hosts
    @hosts ||= hosts!
  end

  # returns a mapping (host name) -> (host key)
  # bypasses memoization
  def hosts!
    @hosts =
      get_list('/hosts').map do |h|
      [h['name'], h['key']]
      end.to_h
  end

  # returns a mapping (host name) -> (log name) -> (log token)
  def hosts_logs
    @hosts_logs ||= hosts_logs!
  end

  # returns a mapping (host name) -> (log name) -> (log token)
  # bypasses log memoization (uses memoized hosts)
  def hosts_logs!
    @hosts_logs =
      hosts.map do |h,k|
      logs = get_list("/hosts/#{k}/")
      [h, logs.map {|l| [l['name'], l['token']] }.to_h]
      end.to_h
  end


  private
  def post_json(request_obj)
    res = Net::HTTP.post_form(@post_uri, request_obj)
    raise IOError, "HTTP status code: #{res.code} - #{res.message}; we sent #{request_obj.inspect}" unless res.is_a?(Net::HTTPSuccess)
    j = JSON.parse(res.body)
    raise ArgumentError, "API returned non-ok #{j.inspect}; we sent #{request_obj.inspect}" unless j['response'] == 'ok'
    res
  end

  def get_list(path)
    path[/^\/?/] = '/'
    uri = URI(@get_uri_base + path)

    res = Net::HTTP.get_response(uri)

    if res.is_a?(Net::HTTPSuccess)
      j = JSON.parse(res.body)
      raise ArgumentError, "API returned non-ok #{j.inspect} requesting #{path}" unless j['response'] == 'ok'
      j['list']
    else
      raise IOError, "HTTP status code: #{res.code} - #{res.message} requesting #{path}"
    end
  end
end

