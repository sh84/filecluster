# FileCluster

A set of scripts to manage files on multiple dc/host/drive.

Item (storage unit)- file or folder.
Storage - folder, usually separate drive.
Policy - rule for selecting storage to store the item and сreate copies.
Copy rule - additional rule for copies сreate.

Daemon monitors the availability of each storage and copy files between them.

If the storage is not available or ended the available space is used another available storage according to the policy.


## Installation

Add this line to your application's Gemfile:

    gem 'filecluster'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install filecluster

## Create policy

Selecting available storage to store item by policy.create_storages (from left to tight).
    
## Copy policy

Used first available storage.
First try copy rules (copy_storages field, from left to right).
After that storage.copy_storages (from left to right).

Copy rule is ruby expression.
Can be used the following variables:

* item_id
* size
* item_copies
* name
* tag
* dir
* src_storage (FC::Storage instance)

## Variables

|name|default value|description|
|:---|:-----------:|:---------|
|global_daemon_host||set fc_daemon when run global daemon task (only in one instance)|
|daemon_cycle_time|30|time between global daemon checks and storages available checks|
|daemon_global_wait_time|120|time between runs global daemon if it does not running|
|daemon_tasks_copy_group_limit|1000|select limit for copy tasks|
|daemon_tasks_delete_group_limit|10000|select limit for delete tasks|
|daemon_tasks_copy_threads_limit|10|copy tasks threads count limit for one storage|
|daemon_tasks_delete_threads_limit|10|delete tasks threads count limit for one storage|
|daemon_copy_tasks_per_host_limit|10|copy tasks count limit for one host|
|daemon_copy_speed_per_host_limit|0|copy tasks speed limit for hosts, change via fc-manage copy_speed|
|daemon_global_tasks_group_limit|1000|select limit for create copy tasks|
|daemon_global_error_items_ttl|86400|ttl for items with error status before delete|
|daemon_global_error_items_storages_ttl|86400|ttl for items_storages with error status before delete|
|daemon_restart_period|86400|time between fc-daemon self restart|

## Usage

TODO: Write usage instructions here

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
