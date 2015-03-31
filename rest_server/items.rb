# encoding: utf-8

require 'grape'
require 'grape-swagger'

module FC
  class RESTAPIitems < Grape::API
    namespace :items, desc: 'operations with FC:Item-s' do
      desc 'Add a new element'
        params do
          requires :path, type: String, desc: 'path to file/dir, scp://path or local path'
          requires :item_name, type: String, desc: 'item name save to database'
          requires :policy, type: String, desc: 'used fc_policy'
          optional :options, type: Hash do
            optional :tag, type: String, desc: 'tag for item'
            optional :outer_id, type: Integer, desc: 'outer id for item'
            optional :replace, type: Boolean, default: false, desc: 'replace item if it exists'
            optional :remove_local, type: Boolean, default: false, desc: 'delete local_path file/dir after add'
          end
        end
        post '/' do
          policy = FC::Policy.where('id = ?', params[:policy].to_s.strip).first
          policy = FC::Policy.where('name = ?', params[:policy].to_s.strip).first unless policy
          raise "Policy #{params[:policy]} not found." unless policy
          item = FC::Item.create_from_local(params[:path].to_s.strip, params[:item_name].to_s.strip, policy, params[:options])
          puts item.inspect
          item
          #error!('path must be at scp://.. or valid local path', 400)
        end
      end
    end
    
end
