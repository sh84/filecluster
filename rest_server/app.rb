# encoding: utf-8

require 'grape'
require 'grape-swagger'
require 'json'
require 'filecluster'
require './items'

module FC
  class RESTAPI < Grape::API
    content_type :xml, 'application/xml'
    content_type :json, 'application/json'
    default_format :json
    rescue_from :all do |e|
      begin
        FC::Error.raise(e, :not_raise => true) unless e.instance_of?(FC::Exception)
      rescue Exception => msg
        puts "error in error! #{msg}"  
      end
      RESTAPI.logger.error e
      Rack::Response.new({
        error: e.message
      }.to_json, 500, {
        "Content-type" => "application/json",
        "Access-Control-Allow-Origin" => '*',
        "Access-Control-Request-Method" => '*'
      }).finish
    end
    
    before do
      header['Access-Control-Allow-Origin'] = '*'
      header['Access-Control-Request-Method'] = '*'
    end
    
    mount FC::RESTAPIitems
    
    add_swagger_documentation(
      hide_documentation_path: true,
      hide_format: true
    )
  end
end
