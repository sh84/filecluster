# FileCluster

A set of scripts to manage files on multiple dc/host/drive.

Item (storage unit)- file or folder.
Storage - folder, usually separate drive.
Policy - rule for selecting storage to store the item and сreate copies.

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

Selecting available storage to copy item by policy.copy_storages (from left to tight) with the nearest copy_id.

## Variables

|name|default value|description|
|:---|:-----------:|:---------|
|global_daemon_host||set fc_daemon when run global daemon task (only in one instance)|
|daemon_cycle_time|30|time between global daemon checks and storages available checks|
|daemon_global_wait_time|120|time between runs global daemon if it does not running|
|daemon_global_tasks_group_limit|1000|limit for select for tasks|
|daemon_global_error_items_ttl|86400|ttl for items with error status before delete|
|daemon_global_error_items_storages_ttl|86400|ttl for items_storages with error status before delete|
|daemon_global_tasks_per_thread|10|tasks count for one task thread|
|daemon_global_tasks_threads_limit|10|tasks threads count limit for one storage|
|daemon_copy_tasks_limit|10|copy tasks count limit for one host|
|daemon_restart_period|86400|time between fc-daemon self restart|

## Usage

TODO: Write usage instructions here

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
