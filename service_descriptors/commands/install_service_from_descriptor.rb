description "installs a service on a target_machine given a service descriptor, not necessarily on the same machine"

param :machine
param! :descriptor_machine
param! "descriptor", "fully qualified path where the service descriptor can be found)"
param "service_root", "path where the service should be installed"

accept_extra_params

on_machine do |machine, params|
  
  parts = params["descriptor"].split("/")
  
  service_name = parts.last.split(".").first
  
  service_root = params.has_key?('service_root') && params['service_root'] != '' ? params['service_root'] :
    parts[0..parts.size-3].join("/")
  
  descriptor_dir = service_root
    
  @op.comment("message" => "installing service '#{service_name}' from #{descriptor_dir} into #{service_root}")
  
  @op.with_machine(params["descriptor_machine"]) do |descriptor_machine|
    
    dotvop_dir = "#{descriptor_dir}/.vop"
    if descriptor_machine.file_exists("file_name" => dotvop_dir)
      @op.comment("message" => "found descriptor dir #{dotvop_dir}")
      descriptor_dir = dotvop_dir 
    end
    
    dotvop_content = descriptor_machine.list_files("directory" => descriptor_dir)
    plugin_names = dotvop_content.select do |file|
      /\.plugin$/.match(file)
    end.map { |x| x.split(".").first }
    raise "found more than one plugin file in #{dotvop_dir}" if plugin_names.size > 1
    raise "could not find plugin file in #{dotvop_dir}" if plugin_names.size == 0
    plugin_name = plugin_names.first
  
    if plugin_name == service_name
        
      # install dependencies
      
      package_dir = "#{descriptor_dir}/packages"
      package_files = descriptor_machine.file_exists("file_name" => package_dir) ? descriptor_machine.list_files("directory" => package_dir) : []
      
      if package_files.include? "vop"
        lines = descriptor_machine.read_lines("file_name" => "#{descriptor_dir}/packages/vop")
        lines.each do |service_spec|
          unless /\//.match(service_spec)
            service_spec += '/' + service_spec
          end
          machine.install_canned_service("service" => service_spec)
        end    
      end
      
      if package_files.include? "github"
        installed_github_projects = machine.list_working_copies_with_projects

        descriptor_machine.read_lines("file_name" => "#{descriptor_dir}/packages/github").each do |line|
          next if /^#/.match(line)
          if installed_github_projects.select { |row| row["project"] == line }.size > 0
            $logger.info("github dependency #{line} already exists locally")
            next
          end
          machine.install_service_from_github("github_project" => line)
        end
      end  
    
      case machine.linux_distribution.split("_").first
      when "centos", "sles"
        if package_files.include? "rpm_repos"
          lines = descriptor_machine.read_lines("file_name" => "#{descriptor_dir}/packages/rpm_repos")
          machine.install_rpm_repo("repo_url" => lines) unless lines.size == 0
        end  
        
        if package_files.include? "rpm"
          lines = descriptor_machine.read_lines("file_name" => "#{descriptor_dir}/packages/rpm")    
          machine.install_rpm_packages_from_file("lines" => lines) unless lines.size == 0
        end
      when "ubuntu"
        if package_files.include? "apt_repos"
          lines = descriptor_machine.read_lines("file_name" => "#{descriptor_dir}/packages/apt_repos")    
          machine.install_apt_repo("repo_url" => lines) unless lines.size == 0
        end
        
        if package_files.include? "apt"
          lines = descriptor_machine.read_lines("file_name" => "#{descriptor_dir}/packages/apt")    
          machine.install_apt_package("name" => lines) unless lines.size == 0
        end
      end
      
      if package_files.include? "gem"
        lines = descriptor_machine.read_lines("file_name" => "#{descriptor_dir}/packages/gem")    
        machine.install_gems_from_file("lines" => lines) unless lines.size == 0
      end
      
    end
    
    # load as a vop plugin
    if ((plugin_name != nil) and (not @op.list_plugins.include?(plugin_name)))
      plugin_file = descriptor_dir + "/#{plugin_name}.plugin"
      if descriptor_machine.file_exists("file_name" => plugin_file)
        descriptor_machine.load_plugin("plugin_file_name" => plugin_file)
      end
    end
    
    # TODO process config
    
    install_command_name = "#{service_name}_install"
    #broker = @op.local_broker
    broker = Thread.current['broker']
    install_command = nil
    begin
      install_command = broker.get_command(install_command_name)
      $logger.info("found install command #{install_command.name}")
    rescue Exception => e
      $logger.debug("did not find install_command #{install_command_name} : #{e.message}")
    end
    
    if install_command != nil    
      param_values = params.clone()
      
      @op.comment("message" => "disabling the null check in the next line wouldn't be a good idea.")
      if params.has_key?('extra_params') && params["extra_params"] != nil #&& params["extra_params"].class == Hash
        param_values.merge!(params["extra_params"])
      end
      
      $logger.info("available param values: \n#{param_values.map { |k,v| "\t#{k}\t#{v}" }.join("\n")}")
       
      params_to_use = {}
      param_values.each do |k,v|
        params_to_use[k] = v if install_command.params.select do |p|
          p.name == k
        end.size > 0
      end
      $logger.info("params_to_use : \n#{params_to_use.map { |k,v| "\t#{k}\t#{v}" }.join("\n")}")
      
      begin
        @op.send(install_command.name.to_sym, params_to_use)
      rescue => detail
        @op.comment("message" => "got a problem while executing install command '#{install_command.name}' : #{detail.message}")
        raise detail
      end
    end
    
    # TODO move this to the end (use service_details instead of list_services_in_directory), otherwise this won't fly for canned services
    service = descriptor_machine.list_services_in_directory("directory" => service_root).select { |x| x["full_name"] == "#{plugin_name}/#{service_name}"}.first
    if service != nil && service.has_key?("cron")
      script_path = machine.write_background_start_script("service" => service_name)
      machine.add_crontab_entry("data" => read_local_template(:crontab, binding()))
    end
    
    if dotvop_content.include? "nagios_commands"
      descriptor_machine.list_files("directory" => "#{descriptor_dir}/nagios_commands").each do |nagios_command|
        @op.add_extra_command(
          "file_name" => nagios_command, 
          "content" => descriptor_machine.read_file("file_name" =>  "#{descriptor_dir}/nagios_commands/#{nagios_command}")
        )
      end      
    end
    
    if machine.file_exists("file_name" => machine.config_dir)
      machine.hash_to_file(
        "file_name" => "#{machine.config_dir}/#{service_name}", 
        "content" => params
      )
    end
  end
  
  @op.without_cache do
    #machine.list_working_copies
    machine.list_installed_services
    
    #machine.list_services
    
    # TODO actually, it would be ok if we invalidated these asynchronously
    if @op.list_plugins.include? 'vop_webapp'
      # TODO reactivate
      #machine.list_machine_tabs
      #machine.list_machine_actions
    end
  end
  
  service = machine.service_details("service" => service_name) 
  
  if service != nil && service.has_key?("outgoing_tcp")
    service["outgoing_tcp"].each do |outgoing|
      case outgoing
      when "all_destinations"
        host_name = machine.name.split('.')[1..10].join('.')
        @op.with_machine(host_name) do |host|
          host.add_forward_include(
            "source_machine" => machine.name,
            "service" => service_name,
            "content" => "iptables -A FORWARD -s #{machine.ipaddress} -p tcp -m state --state NEW -j ACCEPT"
          )
          #host.generate_and_diff_iptables()  # TODO needs 'differ' gem
          host.generate_and_execute_iptables_script()
        end
      else
        raise "unknown destination #{outgoing} in service #{service_name}"
      end
    end
  end
  
  if service["is_startable"]
    machine.start_service("service" => service_name)
  end
end
