#
# Copyright 2016, Noah Kantrowitz
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'shellwords'

require 'chef/resource'
require 'poise'


module PoiseSolaris
  module Resources
    # (see SmfProperty::Resource)
    # @since 1.0.0
    module SmfProperty
      # A `smf_property` resource to SMF service properties.
      #
      # @provides smf_property
      # @action create
      # @example
      #   smf_property 'svc:/network/dhcp/server:ipv4#config/listen_ifnames' do
      #     value 'vnic0'
      #   end
      class Resource < Chef::Resource
        include Poise
        provides(:smf_property)
        actions(:create)

        # @!attribute fmri
        #   Service FMRI. Automatically derived from the name by default.
        #   @return [String]
        attribute(:fmri, kind_of: String, required: true, default: lazy { default_fmri })
        # @!attribute property
        #   Name of the property to manage. Automatically derived from the name
        #   by default.
        #   @return [String]
        attribute(:property, kind_of: String, required: true, default: lazy { default_property })
        # @!attribute type
        #   Property value type. Automatically determined by default.
        #   @return [String, nil, false]
        attribute(:type, kind_of: [String, NilClass, FalseClass])
        # @!attribute value
        #   Value to set.
        #   @return [String, Array<String>]
        attribute(:value, kind_of: [String, Array], required: true)

        private

        # Parse resource name to find the default FMRI.
        #
        # @return [String]
        def default_fmri
          name.split(/#/, 2)[0]
        end

        # Parse resource name to find the default property name.
        #
        # @return [String]
        def default_property
          name.split(/#/, 2)[1]
        end
      end


      # Provider for `smf_property`.
      #
      # @since 1.0.0
      # @see Resource
      # @provides smf_property
      class Provider < Chef::Provider
        include Poise
        provides(:smf_property)

        def load_current_resource
          super
          current_resource.fmri(new_resource.fmri)
          current_resource.property(new_resource.property)
          # Use svccfg to get the currentl value.
          cmd = poise_shell_out!(['svccfg', '-s', new_resource.fmri, 'listprop', new_resource.property])
          props = cmd.stdout.split(/\n/).map {|line| line.split(/\s+/, 3) }.find {|line| line[0] == new_resource.property }
          raise "Unable to find property #{new_resource.property} for service #{new_resource.fmri}" unless props
          current_resource.type(props[1])
          current_resource.value(Shellwords.split(props[2] || ''))
        end

        # `create` action for `smf_property`. Create or update the property.
        #
        # @return [void]
        def action_create
          # If the type isn't given, use the previous type. This should almost
          # always be correct I think.
          type = new_resource.type || current_resource.type
          return if type == current_resource.type && Array(new_resource.value) == Array(current_resource.value)
          value = if new_resource.value.is_a?(Array)
            "(#{Shellwords.join(new_resource.value)})"
          else
            Shellwords.escape(new_resource.value)
          end
          converge_by("setting service property #{new_resource.fmri}#{new_resource.property} to #{type}: #{value}") do
            poise_shell_out!(['svccfg', '-s', new_resource.fmri, 'setprop', new_resource.property, '=', type+':', value])
          end
        end
      end

    end
  end
end
