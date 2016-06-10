require 'bundler/setup'

require 'dotenv'
require 'sinatra'
require 'json'
require 'rubygems/package'
require 'rubygems/commands/push_command'

Dotenv.load

Gem::DefaultUserInteraction.ui = Gem::ConsoleUI.new
Gem.configuration.rubygems_api_key = ENV.fetch('RUBYGEMS_API_KEY')
TOKEN = ENV.fetch('TOKEN')

def get_json(host, path)
  json = Net::HTTP.get(host, path)
  JSON.load(json)
rescue
  raise "Failed to load JSON from #{host}/#{path}:\n#{json}"
end

def push!(name, version)
  spec = Gem::Specification.new do |s|
    s.name = name
    s.version = version
    s.authors = ['example@example.com']
    s.files = [__FILE__]
    s.summary = 'test'
    s.required_ruby_version = '~> 2.0'
    s.required_rubygems_version = '~> 2.6'
    s.add_dependency 'foo', '~> 1.0'
  end
  file = Gem::Package.build(spec)
  Gem::Commands::PushCommand.new.send_gem(file)
ensure
  File.delete(file)
end

def get_dependency_api(gem_name)
  get_json('bundler.rubygems.org', "/api/v1/dependencies.json?gems=#{gem_name}")
end

def get_versions
  Net::HTTP.get('index.rubygems.org', '/versions')
end

def get_info(name)
  Net::HTTP.get('index.rubygems.org', "/info/#{name}")
end

post '/' do
  halt 401, 'token does not match' unless TOKEN == params['token']

  version = params.fetch('version') { Time.now.strftime('%Y.%m.%d.%H.%M.%S') }
  gem_name = ENV.fetch('GEM_NAME')

  dependency_endpoint = get_dependency_api(gem_name)
  versions = get_versions.lines
  info = get_info(gem_name).lines

  if dependency_endpoint.find { |g| g['version'] == version }
    halt 422, "#{gem_name}-#{version} already was pushed"
  end

  begin
    push!(gem_name, version)
  rescue Gem::SystemExitException
    halt 500, "Failed to push: #{$ERROR_INFO}"
  end

  new_gem = get_dependency_api(gem_name) - dependency_endpoint
  case new_gem.size
  when 0 then halt 404, 'gem not added to dependency API'
  when 1
    unless new_gem.first.values_at('name', 'number', 'platform', 'dependencies') == [gem_name, version, 'ruby', [['foo', '~> 1.0']]]
      halt 404, "wrong gem added: #{new_gem}"
    end
  else halt 404, "too many new gems added: #{new_gem}"
  end

  new_versions = versions - get_versions.lines
  unless new_versions.find { |l| l == "#{gem_name} #{version}" }
    halt 404, 'gem not added to versions file'
  end

  new_info = get_info(gem_name).lines - info
  case new_info.size
  when 0 then halt 404, 'gem not added to dependency API'
  when 1 then halt 404, "wrong gem added: #{new_info}" unless new_info =~ /^#{version} /
  else halt 404, "too many new gems added: #{new_info}"
  end

  halt "successfully pushed #{gem_name}-#{version}"
end
