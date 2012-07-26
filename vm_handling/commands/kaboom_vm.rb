description "terminates a machine and re-installs it"

param :machine

param "memory_size", "the amount of memory (in MB) that should be allocated for the new VM", :default_value => 512
param "disk_size", "disk size in GB for the new VM", :default_value => 25
param "vcpu_count", "the number of virtual CPUs to allocate", :default_value => 1

param "ip", "the static IP address for the new machine"

param :github_project
param :git_branch

#param "domain", "the domain at which the service should be available"
param "script_url", "http URL to a script that should be executed at the end of the installation"
param "location", "installation source for guest virtual machine kernel+initrd pair."

accept_extra_params

on_machine do |machine, params|
  short_name = machine.name.split(".").first
  host_name = machine.machine_detail["host_name"]
  @op.with_machine(host_name) do |host|
    host.terminate_vm("name" => short_name)
    
    p = params.clone
    p.delete("machine")
    p["vm_name"] = short_name
    host.setup_vm(p)
  end
  
end   
