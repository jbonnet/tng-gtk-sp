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
require 'net/http'
require 'ostruct'
require 'json'
require 'yaml'
require 'bunny'
require 'tng/gtk/utils/logger'
require_relative './messaging_service'

class FetchWimResourcesMessagingService
  LOGGER=Tng::Gtk::Utils::Logger
  LOGGED_COMPONENT=self.name
  # from https://github.com/sonata-nfv/tng-sp-ia/wiki/RabbitMQ-API-Reference#list-wims
  QUEUE_NAME = 'infrastructure.management.wan.list'
  @@message_service = MessagingService.build(QUEUE_NAME)
  LOGGER.debug(component:LOGGED_COMPONENT, operation:'starting', message:"@@message_service=#{@@message_service.inspect}")
  
  def call(wims_request)
    msg='#'+__method__.to_s
    LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"entered for wims_request=#{wims_request.inspect}")
    queue = @@message_service.queue
    unless queue
      LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"Got nill queue from Messaging service")
      return
    end
    LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"queue=#{queue.inspect}")
    queue.subscribe do |delivery_info, properties, payload|
      LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"delivery_info: #{delivery_info}\nproperties: #{properties}\npayload: #{payload}")
      # We know our own messages, so just skip them
      unless properties[:app_id] == 'tng-gtk-sp'
        LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"Processing: properties[:app_id]: #{properties[:app_id]}")
        # {wim_list: [{uuid: String, name: String, attached_vims: [Strings], attached_endpoints: [Strings], qos: [{node_1: String, node_2: String, latency: int: latency_unit: String, bandwidth: int, bandwidth_unit: String}]}]}
        parsed_payload = YAML.load(payload)
        LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"parsed_payload: #{parsed_payload}")
        #if (parsed_payload['attached_vims'] && parsed_payload['attached_endpoints'] && parsed_payload['qos'])
        if (parsed_payload['wim_list'])
          LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"wim_list: #{parsed_payload['wim_list']}")
          begin
            wim_request = SliceWimResourcesRequest.find_by(id: properties[:correlation_id])
            LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"wim_request=#{wim_request.inspect}")
            if wim_request
              wim_request['wim_list'] = parsed_payload['wim_list'].to_json
              wim_request['status'] = 'COMPLETED'
              wim_request['error'] = ''
              wim_request.save!
            else
              LOGGER.debug(component:LOGGED_COMPONENT, operation:msg, message:"Couldn't find WIMs request for id=#{properties[:correlation_id]}")
            end
          rescue Exception => e
            LOGGER.error(component:LOGGED_COMPONENT, operation:msg, message:"wims_request_error: #{e.message} #{e.backtrace.inspect} ")
          ensure
            InfrastructureRequest.connection_pool.flush!
            InfrastructureRequest.clear_active_connections!
          end
        end
      end
      @@message_service.publish('', wims_request.id)
    end
  end
end


