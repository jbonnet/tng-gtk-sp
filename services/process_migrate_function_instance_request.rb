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

class ProcessMigrateFunctionInstanceRequest < ProcessRequestBase
  LOGGER=Tng::Gtk::Utils::Logger
  LOGGED_COMPONENT=self.name
  
  def self.call(params)
    new.call(params)
  end
  
  def call(params)
    msg='#'+__method__.to_s
    LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"params=#{params}")
    valid = valid_request?(params)
    
    if (valid && valid.key?(:error) )
      LOGGER.error(component:LOGGED_COMPONENT, operation: msg, message:"validation failled with error #{valid[:error]}")
      return valid
    end
    
    completed_params = complete_params(params)
    LOGGER.debug(component:LOGGED_COMPONENT, operation: msg, message:"completed params=#{completed_params}")
    begin
      migration_request = Request.create(completed_params).as_json
    ensure
      Request.clear_active_connections!
    end
    unless migration_request
      LOGGER.error(component:LOGGED_COMPONENT, operation: msg, message:"Failled to create migration request for function instance '#{params[:instance_uuid]}'")
      return {error: "Failled to create the migration request #{params}"}
    end
    LOGGER.debug(component:LOGGED_COMPONENT, operation: msg, message:"migration_request=#{migration_request}")
    message = build_message(completed_params[:instance_uuid], completed_params[:vnf_uuid], completed_params[:vim_uuid])
    begin
     published_response = MessagePublishingService.call(message, :migrate_function, migration_request[:id])
     LOGGER.debug(component:LOGGED_COMPONENT, operation: msg, message:"published_response=#{published_response}")
    rescue StandardError => e
      LOGGER.error(component:LOGGED_COMPONENT, operation: msg, message:"(#{e.class}) #{e.message}\n#{e.backtrace.split('\n\t')}")
      return {error: "#{LOGGED_COMPONENT}#{msg} (#{__LINE__}):\n#{e.message}\n#{e.backtrace.split('\n\t')}"}
    end
    migration_request
  end
  
  def self.enrich_one(request)
    new.enrich_one(request)
  end
  def enrich_one(request)
    msg='.'+__method__.to_s
    LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"request=#{request.inspect} (class #{request.class})")
    request
  end
  
  private
  def valid_request?(params)
=begin
topic: service.instance.migrate
payload:

---
service_instance_uuid: <id of the service instance>
vnf_uuid: <id of the vnf instance that needs to be migrated>
vim_uuid: <id of the vim that the vnf needs to be migrated to>
data = {
            "instance_uuid": instance_uuid,
            "request_type": "MIGRATE_FUNCTION",
            "vnf_uuid": vnf_uuid,
            "vim_uuid": vim_uuid
        }
=end
    msg='.'+__method__.to_s
    LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"params=#{params}")

    return {error: "The service instance UUID must be present"} unless params.key?(:instance_uuid)
    return {error: "The service instance UUID must be valid"} unless uuid_valid?(params[:instance_uuid])
    return {error: "The VNF UUID must be present"} unless params.key?(:vnf_uuid)
    return {error: "The VNF UUID must be valid"} unless uuid_valid?(params[:vnf_uuid])
    return {error: "The VIM UUID must be present"} unless params.key?(:vim_uuid)
    return {error: "The VIM UUID must be valid"} unless uuid_valid?(params[:vim_uuid])
    {}
  end
  
  def complete_params(params)
    params
  end
  
  def build_message(instance_uuid, vnf_uuid, vim_uuid)
    msg='.'+__method__.to_s
    LOGGER.debug(component:LOGGED_COMPONENT, operation: msg, message:"instance_uuid=#{instance_uuid} vnf_uuid=#{vnf_uuid} vim_uuid=#{vim_uuid}")
    message = {}
    message['service_instance_uuid'] = instance_uuid
    message['vnf_uuid'] = vnf_uuid
    message['vim_uuid'] = vim_uuid
    LOGGER.debug(component:LOGGED_COMPONENT, operation: msg, message:"message=#{message}")
    message.to_yaml.to_s
  end  
  
  def enrich_params(params)
    msg='.'+__method__.to_s
    LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"params=#{params}")
    params
  end
  
  def uuid_valid?(uuid)
    return true if (uuid =~ /[a-f0-9]{8}-([a-f0-9]{4}-){3}[a-f0-9]{12}/) == 0
    false
  end
end
