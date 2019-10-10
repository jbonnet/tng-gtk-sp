## Copyright (c) 2015 SONATA-NFV, 2017 5GTANGO [, ANY ADDITIONAL AFFILIATION]
## ALL RIGHTS RESERVED.
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##     http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.
##
## Neither the name of the SONATA-NFV, 5GTANGO [, ANY ADDITIONAL AFFILIATION]
## nor the names of its contributors may be used to endorse or promote
## products derived from this software without specific prior written
## permission.
##
## This work has been performed in the framework of the SONATA project,
## funded by the European Commission under Grant number 671517 through
## the Horizon 2020 and 5G-PPP programmes. The authors would like to
## acknowledge the contributions of their colleagues of the SONATA
## partner consortium (www.sonata-nfv.eu).
##
## This work has been performed in the framework of the 5GTANGO project,
## funded by the European Commission under Grant number 761493 through
## the Horizon 2020 and 5G-PPP programmes. The authors would like to
## acknowledge the contributions of their colleagues of the 5GTANGO
## partner consortium (www.5gtango.eu).
# encoding: utf-8
require 'securerandom'
require 'net/http'
require 'uri'
require 'ostruct'
require 'json'
require 'yaml'
require_relative './process_request_base'
require_relative '../models/request'
require 'tng/gtk/utils/logger'

class ProcessCreateSliceInstanceRequest < ProcessRequestBase
  LOGGER=Tng::Gtk::Utils::Logger
  LOGGED_COMPONENT=self.name
  NO_SLM_URL_DEFINED_ERROR='The SLM_URL ENV variable needs to be defined and pointing to the Slice Manager component, where to request new Network Slice instances'
  SLM_URL = ENV.fetch('SLM_URL', '')
  if SLM_URL == ''
    LOGGER.debug(component:LOGGED_COMPONENT, operation:'fetching SLM_URL ENV variable', message:NO_SLM_URL_DEFINED_ERROR)
    raise ArgumentError.new(NO_SLM_URL_DEFINED_ERROR) 
  end
  SLICE_INSTANCE_CHANGE_CALLBACK_URL = ENV.fetch('SLICE_INSTANCE_CHANGE_CALLBACK_URL', 'http://tng-gtk-sp:5000/requests')
  
  def self.call(params)
    msg='.'+__method__.to_s
    LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"params=#{params}")
    begin
      valid = valid_request?(params)
      if (valid && valid.is_a?(Hash) && valid.key?(:error) && !valid[:error].to_s.empty?)
        LOGGER.error(component:LOGGED_COMPONENT, operation:msg, message:"validation failled with error '#{valid[:error]}'")
        return valid
      end
      params[:service_uuid] = params.delete(:nst_id)
      begin
        instantiation_request = Request.create(params)
      ensure
        Request.connection_pool.flush!
        Request.clear_active_connections!
      end
      
      LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"instantiation_request=#{instantiation_request.inspect}")
      unless instantiation_request
        LOGGER.error(component:LOGGED_COMPONENT, operation:msg, message:"Failled to create instantiation_request for slice template '#{params[:nstId]}'")
        return {error: "Failled to create instantiation request for slice template '#{params[:service_uuid]}'"}
      end
      # pass it to the Slice Manager
      # {"nstId":"3a2535d6-8852-480b-a4b5-e216ad7ba55f", "name":"Testing", "description":"Test desc"}
      # the user callback is saved in the request
      # CREATE_SLICE doesn't need customer info
      params.delete(:customer_name)
      params.delete(:customer_email)
      
      enriched_params = params #enrich_params(params)
      enriched_params[:nstId] = params.delete(:service_uuid)
      enriched_params[:callback] = "#{SLICE_INSTANCE_CHANGE_CALLBACK_URL}/#{instantiation_request['id']}/on-change"
      LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"enriched_params=#{enriched_params}")
      request = create_slice(enriched_params)
      unless request 
        LOGGER.error(component:LOGGED_COMPONENT, operation:msg, message:"Failled to create slice instance for slice template '#{params[:nstId]}'")
        return {error: "Failled to create slice instance for slice template '#{params[:service_uuid]}'"}
      end
      LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"request=#{request}")
      if (request.is_a?(Hash) && request.key?(:error))
        instantiation_request['status'] = 'ERROR'
        instantiation_request['error'] = request[:error]
      else
        instantiation_request['status'] = request[:"nsi-status"]
      end

      begin
        instantiation_request.save
      ensure
        Request.connection_pool.flush!
        Request.clear_active_connections!
      end
      return instantiation_request.as_json
    rescue StandardError => e
      LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"#{e.message} (#{e.class}):#{e.backtrace.split('\n\t')}")
      return nil
    end
  end
  
  # "/api/nsilcm/v1/nsi/on-change"
  # @app.route(API_ROOT+API_NSILCM+API_VERSION+API_NSI+'/update_NSIservinstance', methods=['POST'])
  # GET http://tng-slice-mngr:5998/api/nst/v1/descriptors
  def self.process_callback(event)
    msg='.'+__method__.to_s
    LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"event=#{event}")
    result, user_callback = save_result(event)
    notify_user(result, user_callback) unless user_callback.to_s.empty?
    LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"result=#{result}")
    result
  end
  
  def self.enrich_one(request)
    msg='.'+__method__.to_s
    LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"request=#{request.inspect} (class #{request.class})")
    request
  end
  
  private  
  def self.save_result(event)
    msg='.'+__method__.to_s

    begin
      original_request = Request.find(event[:original_event_uuid])
    ensure
      Request.connection_pool.flush!
      Request.clear_active_connections!
    end
    LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"original request = #{original_request.inspect}")
    #body = JSON.parse(request.body.read, quirks_mode: true, symbolize_names: true)
    #original_request['status'] = body[:status]
    original_request['status'] = event[:status]
    original_request['name'] = event[:name]
    original_request['instance_uuid'] = event[:instance_uuid] 
    begin
      original_request.save
    ensure
      Request.connection_pool.flush!
      Request.clear_active_connections!
    end    
    [original_request.as_json, event[:callback]]
  end
  
  def self.notify_user(result, user_callback)
    msg='.'+__method__.to_s
    LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"entered, result=#{result}, user_callback=#{user_callback}")
    
    uri = URI.parse(user_callback)

    # Create the HTTP objects
    http = Net::HTTP.new(uri.host, uri.port)
    request = Net::HTTP::Post.new(uri)
    request.body = result.to_json
    request['Content-Type'] = 'application/json'

    # Send the request
    begin
      response = http.request(request)
      LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"response=#{response}")
      case response
      when Net::HTTPSuccess, Net::HTTPCreated
        body = response.body
        LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"#{response.code} body=#{body}")
        return JSON.parse(body, quirks_mode: true, symbolize_names: true)
      else
        return {error: "#{response.message}"}
      end
    rescue Exception => e
      LOGGER.error(component:LOGGED_COMPONENT, operation:msg, message:"Failled to post to user's callback #{user_callback} with message #{e.message}")
    end
    nil
  end

  def self.valid_request?(params)
    msg='.'+__method__.to_s
    # { "request_type":"CREATE_SLICE", "nstId":"3a2535d6-8852-480b-a4b5-e216ad7ba55f", "name":"Testing", "description":"Test desc", "slice_instance_ready_callback":"http://..."}
    # template existense is tested within the SLM
    # GET http://tng-slice-mngr:5998/api/nst/v1/descriptors
    LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"params=#{params}")
    return {error: "Request type #{params[:request_type]} is not CREATE_SLICE"} unless params[:request_type].upcase == "CREATE_SLICE"
    return {error: "Slice instantiation request needs a nst_id"} unless params.key?(:nst_id)
    true
  end
  
  def self.enrich_params(params)
    msg='.'+__method__.to_s
    LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"params=#{params}")
    begin 
      params[:instantiation_params] = JSON.parse(params.fetch(:instantiation_params, '[]'))
      LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"params[:instantiation_params]=#{params[:instantiation_params]}")
    rescue JSON::ParserError => e
      LOGGER.error(component:LOGGED_COMPONENT, operation:msg, message:"Failled to parse slice instantiation parameters '#{instantiation_params}'")
    end
    params
  end
  
  def self.create_slice(params)
    msg='.'+__method__.to_s
    # POST http://tng-slice-mngr:5998/api/nsilcm/v1/nsi, with body {...}
    site = SLM_URL+'/nsilcm/v1/nsi'
    LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"params=#{params} site=#{site}")
    uri = URI.parse(site)

    # Create the HTTP objects
    http = Net::HTTP.new(uri.host, uri.port)
    request = Net::HTTP::Post.new(uri)
    request.body = params.to_json
    request['Content-Type'] = 'application/json'

    # Send the request
    begin
      response = http.request(request)
      LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"response=#{response}")
      case response
      when Net::HTTPSuccess, Net::HTTPCreated
        body = response.body
        LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"#{response.code} body=#{body}")
        json_body = JSON.parse(body, quirks_mode: true, symbolize_names: true)
        json_body[:service_uuid] = json_body.delete(:nst_id) if json_body.key?(:nst_id)
        LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"json_body=#{json_body}")
        return json_body
      else
        return {error: "Creating the slice: #{response.code} (#{response.message}): #{params}"}
      end
    rescue Exception => e
      LOGGER.error(component:LOGGED_COMPONENT, operation:msg, message:"#{e.message}")
      return {error: "Creating the slice: #{e.message}\n#{e.backtrace.join("\n\t")}"}
    end
  end
end
