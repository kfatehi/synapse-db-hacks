#!/usr/bin/env ruby
# example usage 
# ./get.sh
# ./cleandb.rb -p imessage -i bridge-dev -v
# ./push.sh
require "sqlite3"
require "slop"

$opts = Slop.parse do |o|
  o.string '-p', '--prefix', 'service prefix'
  o.array '-i', '--ignores', 'list of ignore(s)'
  o.bool '-d', '--delete', 'set this flag if you want to delete'
  o.bool '-v', '--verbose', 'increase verbosity'
end

$verbose = $opts[:verbose]
$delete = $opts[:delete]

p $opts.to_hash

$service_prefix = $opts[:prefix]

if !$service_prefix
  puts "pass in a service prefix you want to clear out"
  exit()
end

puts "gonna clear out any trace of users or rooms pertaining to service prefix #{$service_prefix}"

$db = SQLite3::Database.new "homeserver.db"

def makeDefaultConditions(field)
  conditions = [
    %{where #{field} like "%#{$service_prefix}%"}
  ]
  conditions << $opts[:ignores].map do |i|
    %{and #{field} not like "%#{i}%"}
  end
end

def runQuery(t)
  table = t[:table]
  handler = t[:handler] || Proc.new() do |rows|
    rows.each do |row|
      puts row[0]
    end
  end
  conditions = t[:conditions] || []
  if $delete and t[:delete]
    action = "delete"
  else
    action = "select *"
  end
  query = []
  query << "#{action} from #{table}"
  query << conditions
  query = query.join("\n")
  puts "\n#{query}\n\n" if $opts[:verbose]
  handler.($db.execute(query))
end

$room_ids = [];
$user_ids = [];

def addRoomId(rid)
  $room_ids << rid
  $room_ids.uniq!
  puts rid if $verbose
end

def addRoomIds(ids)
  ids.each{|i| addRoomId i}
end

def addUserId(id)
  $user_ids << id
  $user_ids.uniq!
  puts id if $verbose
end

def addUserIds(ids)
  ids.each{|i| addUserId i}
end

def whereInRoomIds(keyName="room_id")
  "where #{keyName} in (#{$room_ids.map{|i| %{"#{i}"} }.join(', ')})"
end

def whereInUserIds(keyName="name")
  "where #{keyName} in (#{$room_ids.map{|i| %{"#{i}"} }.join(', ')})"
end

# get all bridge-related room ids

runQuery(
  table:'rooms',
  # rooms made by previous bots
  conditions: makeDefaultConditions('creator'),
  handler: -> (rows) {
    ids = rows.map{|r| r[0]}
    addRoomIds(ids);
  }
)

runQuery(
  table:'room_aliases',
  # rooms made by new version
  conditions: makeDefaultConditions('room_alias'),
  handler: -> (rows) {
    ids = rows.map{|r| r[1]}
    addRoomIds(ids);
  }
)

# get all bridge-related user ids
runQuery(
  table:'users',
  conditions: makeDefaultConditions('name'),
  handler: -> (rows) {
    ids = rows.map{|r| r[0]}
    addUserIds(ids);
  }
)

# delete all profiles
runQuery(
  table:'profiles',
  conditions: makeDefaultConditions('user_id'),
  delete: true
)

# delete all room memberships
runQuery(
  table:'room_memberships',
  conditions: makeDefaultConditions('user_id'),
  delete: true
)

# delete stuff related to the room ids
runQuery(
  table:'room_names',
  conditions: [ whereInRoomIds() ],
  delete: true
)

# any lingering memberships
runQuery(
  table:'room_memberships',
  conditions: [ whereInRoomIds() ],
  delete: true
)

# whatever this is
runQuery(
  table:'room_depth',
  conditions: [ whereInRoomIds() ],
  delete: true
)

runQuery(
  table:'room_aliases',
  conditions: [ whereInRoomIds() ],
  delete: true
)

runQuery(
  table:'room_alias_servers',
  conditions: makeDefaultConditions('room_alias'),
  delete: true
)

# and then delete all those high level items

runQuery(
  table:'rooms',
  conditions: [ whereInRoomIds() ],
  delete: true
)

runQuery(
  table:'room_aliases',
  conditions: makeDefaultConditions('room_alias'),
  delete: true
)

runQuery(
  table:'users',
  conditions: [ whereInUserIds("name") ],
  delete: true
)
