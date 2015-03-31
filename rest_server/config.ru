$:.unshift File.expand_path('../lib', File.dirname(__FILE__))
$:.unshift File.expand_path('.', File.dirname(__FILE__))

require 'filecluster'
require 'utils'
require 'psych'
require 'puma'
require 'rack'
require './app'

default_db_config = File.expand_path('../bin', File.dirname(__FILE__))+'/db.yml'
descriptions = {
  :config      => {:short => 'c',  :full => 'config',    :default => default_db_config, :text => "path to db.yml file, default #{default_db_config}"},
  :curr_host   => {:short => 'h', :full => 'host',       :default => FC::Storage.curr_host, :text => "Host for storages, default #{FC::Storage.curr_host}"}
}
desc = %q{Run FileCluster rest server.
Usage: fc-daemon [options]}
options = option_parser_init(descriptions, desc, ENV['RUN_ARGS'].to_s.split)
FC::Storage.instance_variable_set(:@uname, options[:curr_host]) if options[:curr_host] && options[:curr_host] != FC::Storage.curr_host
db_options = Psych.load(File.read(options[:config]))
FC::DB.connect_by_config(db_options.merge(:reconnect => true))

use Rack::Static, :urls => ["/site"], :root => 'public', :index => 'index.html'

run FC::RESTAPI

module Twitter
  class API < Grape::API
    version 'v1', using: :header, vendor: 'twitter'
    format :json
    prefix :api

    helpers do
      def current_user
        @current_user ||= User.authorize!(env)
      end

      def authenticate!
        error!('401 Unauthorized', 401) unless current_user
      end
    end
    
    get :test do
      "fgfg"
      
    end

    resource :statuses do
      desc "Return a public timeline."
      get :public_timeline do
        Status.limit(20)
      end

      desc "Return a personal timeline."
      get :home_timeline do
        authenticate!
        current_user.statuses.limit(20)
      end

      desc "Return a status."
      params do
        requires :id, type: Integer, desc: "Status id."
      end
      route_param :id do
        get do
          Status.find(params[:id])
        end
      end

      desc "Create a status."
      params do
        requires :status, type: String, desc: "Your status."
      end
      post do
        authenticate!
        Status.create!({
          user: current_user,
          text: params[:status]
        })
      end

      desc "Update a status."
      params do
        requires :id, type: String, desc: "Status ID."
        requires :status, type: String, desc: "Your status."
      end
      put ':id' do
        authenticate!
        current_user.statuses.find(params[:id]).update({
          user: current_user,
          text: params[:status]
        })
      end

      desc "Delete a status."
      params do
        requires :id, type: String, desc: "Status ID."
      end
      delete ':id' do
        authenticate!
        current_user.statuses.find(params[:id]).destroy
      end
    end
  end
end
