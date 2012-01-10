description 'returns a list of accounts at hosting providers'

display_type :table
add_columns [ :type, :alias ]

mark_as_read_only

with_contributions do |result, params|
  
  result.sort_by do |item|
    [ item["contributed_by"], item["alias"] ]
  end
end
