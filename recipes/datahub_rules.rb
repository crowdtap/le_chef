require 'json'

leproxy_service = resources('service[leproxy]').provider_for_action(:start).load_current_resource

if !leproxy_service.running
  Chef::Log.warn("Trying to automate leproxy rules when service not running. We can't trust the config for before. Giving up!")
  return
end

#at compile time, i.e. before this run can overwrite the config to have NO rules
config = JSON.parse(IO.read("#{node['le']['datahub']['local_path']}/leproxy.config"))
known_patterns = Set.new(config["rules"].map { |r| r["pattern"] })

requested_patterns = Set.new()
patterns_to_rules = {}

nodes_requesting_patterns = search(:node, 'le_datahub_rules_needed:*')
nodes_requesting_patterns.each do |node|
  node.le.rules_needed.each do |rule|
    rule.pattern ||= LogentriesAPI.default_pattern(rule.host, rule.log)

    patterns_to_rules[rule.pattern] = rule
    requested_patterns.add rule.pattern
  end
end

new_patterns = requested_patterns - known_patterns

if !new_patterns.empty?
  le = LogentriesAPI.new(node['le']['account_key'])

  new_patterns.each do |p|
    r = patterns_to_rules[p]

    #Assuming this recipe is included last-ish in run_list, we do most of the
    #work above at compiletime early in the run, but we want to delay the actual
    #API calls until almost the end of the run, cause depending how the API is
    #feeling, it may very well timeout the chef run.
    ruby_block "Creating Datahub Rule: /#{r.pattern}/ -> hosts/#{r.host}/#{r.log}"do
      block { le.create_datahub_mapping(r.host, r.log, r.pattern, r.name) }
      action :run
    end
  end
end
