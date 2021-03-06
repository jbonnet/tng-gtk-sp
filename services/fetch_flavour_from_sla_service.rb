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
require 'tng/gtk/utils/logger'
require 'tng/gtk/utils/fetch'

class FetchFlavourFromSLAService < Tng::Gtk::Utils::Fetch
  SLA_MNGR_URL = ENV.fetch('SLA_MNGR_URL', '')
  NO_SLA_MNGR_URL_DEFINED_ERROR='The SLA_MNGR_URL ENV variable needs to defined and pointing to the SLA Manager'  
  if SLA_MNGR_URL == ''
    LOGGER.error(component:'FetchFlavourFromSLAService', operation:'fetching SLA_MNGR_URL ENV variable', message:NO_SLA_MNGR_URL_DEFINED_ERROR)
    raise ArgumentError.new(NO_SLA_MNGR_URL_DEFINED_ERROR) 
  end  
  self.site=SLA_MNGR_URL+'/mgmt/deploymentflavours'
  LOGGER.info(component:self.name, operation:'site definition', message:"self.site=#{self.site}")
  def self.call(service_uuid, sla_uuid)
    msg=self.name+'#'+__method__.to_s
    began_at=Time.now.utc
    LOGGER.info(start_stop: 'START', component:self.name, operation:msg, message:"service_uuid=#{service_uuid} sla_uuid=#{sla_uuid}")
    #curl -v -H "Content-type:application/json" http://int-sp-ath.5gtango.eu:8080/tng-sla-mgmt/api/slas/v1/mgmt/deploymentflavours/{nsd_uuid}/{sla_uuid}
    
    uri = URI.parse("#{self.site}/#{service_uuid}/#{sla_uuid}")
    request = Net::HTTP::Get.new(uri)
    request['content-type'] = 'application/json'
    response = Net::HTTP.start(uri.hostname, uri.port) {|http| http.request(request)}
    LOGGER.debug(component:self.name, operation:msg, message:"response=#{response.inspect}")
    case response
    when Net::HTTPSuccess
      body = response.read_body
      LOGGER.debug(component:self.name, operation:msg, message:"body=#{body}", status: '200')
      result = JSON.parse(body, quirks_mode: true, symbolize_names: true)
      LOGGER.debug(start_stop: 'STOP', component:self.name, operation:msg, message:"result=#{result} site=#{self.site}", time_elapsed: Time.now.utc - began_at)
      return result[:d_flavour_name]
    when Net::HTTPNotFound
      LOGGER.debug(start_stop: 'STOP', component:self.name, operation:msg, message:"body=#{body}", status:'404', time_elapsed: Time.now.utc - began_at)
      return ''
    else
      LOGGER.error(start_stop: 'STOP', component:self.name, operation:msg, message:"#{response.message}", status:'404', time_elapsed: Time.now.utc - began_at)
      return nil
    end
  end
end
