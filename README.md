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

## Usage

TODO: Write usage instructions here

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
