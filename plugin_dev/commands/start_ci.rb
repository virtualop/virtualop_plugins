param :machine
param! "host", "a host to run CI on"

on_machine do |machine, params|
  #machine.vop_call("logging" => "true", "command" => "vop_ci machine=#{params["host"]}")
  machine.vop_call("logging" => "true", "command" => "trigger_stack_rollout machine=#{params["host"]} stack=minimal_platform")
end  
