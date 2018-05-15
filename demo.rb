
# наполнение кусoчками filecluster


$:.unshift File.expand_path('./lib', File.dirname(__FILE__))
require 'filecluster'
require 'byebug'

ssh_host_storage = 'filecluster1-ssh'

policy =  FC::Policy.filter_by_host(ssh_host_storage).first
FC::Storage.instance_variable_set(:@uname, ssh_host_storage)

while true do
   i =  Time.now.to_i
   a = i.to_s[0..1]
   b = i.to_s[2..3]
   system("mkdir -p /data/channel1/#{a}/#{b}")
   path = "/data/channel1/#{a}/#{b}/#{i}.txt"
   File.open(path, 'w') do |f|
     f.write(i)
   end
   puts "create #{i}.txt"
   name = path.sub(/.*channel1\//, '')  # обрезаем префикс папки хранения
   FC::Item.create_from_local(path, name, policy,
     :tag => 'demo',
     :outer_id => i,
   )
   sleep 2
end
