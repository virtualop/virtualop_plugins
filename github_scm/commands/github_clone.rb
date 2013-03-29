description 'clones a project from github onto a machine'

github_params

param :machine

param! "github_project"
param :git_branch
param :git_tag
param "directory", "the target directory to checkout into (defaults to $HOME/project_name)"

on_machine do |machine, params|
  git_url = "https://github.com/#{params["github_project"]}.git"
  
  begin
    # TODO this should happen only if github_params are present  
    project_row = @op.list_github_repos(params).select { |x| x["full_name"] == params["github_project"] }.first
    if project_row != nil && project_row["private"] == "true"
      git_url = "git@github.com:#{params["github_project"]}.git"
    end
  rescue => detail
    raise detail unless /^need either/.match(detail.message)
  end
      
  clone_params = {
    "git_url" => git_url
  }.merge_from params, :git_tag, :git_branch, :directory
  machine.git_clone(clone_params)  
end