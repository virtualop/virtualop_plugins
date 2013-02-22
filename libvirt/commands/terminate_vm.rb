description 'destroys and undefines a VM'

param :machine
param :vm

notifications

on_machine do |machine, params|
  state = "unknown"
  @op.without_cache do # to prevent situations where the vop has the wrong state
    state = machine.list_vms.select do |vm|
      vm["name"] == params["name"]
    end.first["state"]
  end
  
  if state == "running"
    machine.destroy_vm("name" => params["name"])
    
    @op.wait_until("interval" => 5, "timeout" => 30, 
      "error_text" => "could not find a machine with name '#{params["name"]}' that is shut off") do
      candidates = machine.list_vms.select do |row|
        row["name"] == params["name"] and
        row["state"] == "shut off"
      end
      candidates.size > 0
    end
  end
  
  machine.undefine_vm("name" => params["name"])
  
  machine.ssh_and_check_result("command" => "virsh vol-delete #{params["name"]}.img --pool default")
    
  @op.cleanup_machine("machine" => params["name"] + '.' + params["machine"])
  
  @op.without_cache do 
    machine.list_vms
  end
end

