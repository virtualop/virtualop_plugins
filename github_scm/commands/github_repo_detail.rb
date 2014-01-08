github_params
param! :github_project

#add_columns [ :full_name ]

display_type :hash

#mark_as_read_only
#no_cache

execute do |params|
  org_name = params['github_project'].split('/').first
  rows = org_name == @op.github_user(params)['login'] ?
    @op.list_github_repos(params) :
    @op.list_repos_for_org(params.merge('org' => org_name))
  row = rows.select { |x| x['full_name'] == params['github_project'] }.first
  unless row
    raise "sanity check failed: github project #{params['github_project']} not found in user or organisation repos"
  end
  result = @op.inspect_github_repos(params.merge('project_data' => row)).first
  
  if result && result['services'] && result['services'].size > 0
    service = result['services'].first
    begin
      if service.has_key?('install_command_name') and service['install_command_name'] != nil
        result['install_command'] = @op.broker.get_command(service["install_command_name"])
      end
    rescue RHCP::RhcpException => e
      $logger.warn("cannot load install command for service #{service["name"]} : #{e}")
      raise e
    end
  end
  
  result  
end