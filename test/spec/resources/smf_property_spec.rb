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

require 'spec_helper'

describe PoiseSolaris::Resources::SmfProperty do
  context 'with a svc:// FMRI' do
    recipe do
      smf_property 'svc://network/dns/client#config/nameserver'
    end

    it { is_expected.to create_smf_property('svc://network/dns/client#config/nameserver').with(fmri: 'svc://network/dns/client', property: 'config/nameserver')}
  end # /context with a svc:// FMRI

  context 'with a non-svc:// FMRI' do
    recipe do
      smf_property 'network/dns/client#config/nameserver'
    end

    it { is_expected.to create_smf_property('network/dns/client#config/nameserver').with(fmri: 'network/dns/client', property: 'config/nameserver')}
  end # /context with a non-svc:// FMRI

  describe '#load_current_resource' do
    let(:new_resource) do
      described_class::Resource.new('', chef_run.run_context).tap do |r|
        r.fmri('myfmri')
        r.property('mypg/myprop')
      end
    end
    let(:new_provider) { new_resource.provider_for_action(:create) }
    subject { new_provider.load_current_resource; new_provider.current_resource }

    context 'with a single-value property' do
      before { allow(new_provider).to receive(:poise_shell_out!).with(%w{svccfg -s myfmri listprop mypg/myprop}).and_return(double(stdout: 'mypg/myprop    astring    myvalue')) }
      its(:type) { is_expected.to eq 'astring' }
      its(:value) { is_expected.to eq %w{myvalue} }
    end # /context with a single-value property

    context 'with a multi-value property' do
      before { allow(new_provider).to receive(:poise_shell_out!).with(%w{svccfg -s myfmri listprop mypg/myprop}).and_return(double(stdout: 'mypg/myprop    astring    myvalue1 myvalue2')) }
      its(:type) { is_expected.to eq 'astring' }
      its(:value) { is_expected.to eq %w{myvalue1 myvalue2} }
    end # /context with a multi-value property

    context 'with a non-string property' do
      before { allow(new_provider).to receive(:poise_shell_out!).with(%w{svccfg -s myfmri listprop mypg/myprop}).and_return(double(stdout: 'mypg/myprop    net_address    1.2.3.4')) }
      its(:type) { is_expected.to eq 'net_address' }
      its(:value) { is_expected.to eq %w{1.2.3.4} }
    end # /context with a non-string property
  end # /describe #load_current_resource

  describe 'action :create' do
    let(:new_resource) do
      described_class::Resource.new('', chef_run.run_context).tap do |r|
        r.fmri('myfmri')
        r.property('mypg/myprop')
      end
    end
    let(:new_provider) do
      new_resource.provider_for_action(:create).tap do |p|
        p.current_resource = current_resource
      end
    end
    let(:current_type) { 'astring' }
    let(:current_value) { [''] }
    let(:current_resource) { double('current_resource', type: current_type, value: current_value) }
    subject { new_provider.action_create; new_provider }

    context 'with a single-value property' do
      before { new_resource.value('myvalue') }
      it do
        expect(new_provider).to receive(:poise_shell_out!).with(%w{svccfg -s myfmri setprop mypg/myprop = astring: myvalue})
        expect(subject.resource_updated?).to be true
      end
    end # /context with a single-value property

    context 'with a single-value property that is already set' do
      let(:current_value) { %w{myvalue} }
      before { new_resource.value('myvalue') }
      it do
        expect(new_provider).to_not receive(:poise_shell_out!)
        expect(subject.resource_updated?).to be false
      end
    end # /context with a single-value property that is already set

    context 'with a multi-value property' do
      before { new_resource.value(%w{myvalue1 myvalue2}) }
      it do
        expect(new_provider).to receive(:poise_shell_out!).with(%w{svccfg -s myfmri setprop mypg/myprop = astring:} + ['(myvalue1 myvalue2)'])
        expect(subject.resource_updated?).to be true
      end
    end # /context with a multi-value property

    context 'with a multi-value property that is already set' do
      let(:current_value) { %w{myvalue1 myvalue2} }
      before { new_resource.value(%w{myvalue1 myvalue2}) }
      it do
        expect(new_provider).to_not receive(:poise_shell_out!)
        expect(subject.resource_updated?).to be false
      end
    end # /context with a multi-value property that is already set

    context 'with a non-string property' do
      let(:current_type) { 'net_address' }
      before { new_resource.value('1.2.3.4') }
      it do
        expect(new_provider).to receive(:poise_shell_out!).with(%w{svccfg -s myfmri setprop mypg/myprop = net_address: 1.2.3.4})
        expect(subject.resource_updated?).to be true
      end
    end # /context with a non-string property

    context 'with an explicit non-string property' do
      before { new_resource.value('1.2.3.4'); new_resource.type('net_address') }
      it do
        expect(new_provider).to receive(:poise_shell_out!).with(%w{svccfg -s myfmri setprop mypg/myprop = net_address: 1.2.3.4})
        expect(subject.resource_updated?).to be true
      end
    end # /context with an explicit non-string property
  end # /describe action :create

  context 'with real-world data' do
    step_into(:smf_property)

    context 'dhcp listen_ifnames' do
      recipe do
        smf_property 'network/dhcp/server:ipv4#config/listen_ifnames' do
          value 'vnic0'
        end
      end

      it do
        expect_any_instance_of(described_class::Provider).to receive(:poise_shell_out!).with(%w{svccfg -s network/dhcp/server:ipv4 listprop config/listen_ifnames}).and_return(double(stdout: "config/listen_ifnames astring\n"))
        expect_any_instance_of(described_class::Provider).to receive(:poise_shell_out!).with(%w{svccfg -s network/dhcp/server:ipv4 setprop config/listen_ifnames = astring: vnic0})
        run_chef
      end
    end # /context dhcp listen_ifnames

    context 'dns nameservers' do
      recipe do
        smf_property 'network/dns/client#config/nameserver' do
          value %w{8.8.8.8 8.8.4.4}
        end
      end

      it do
        expect_any_instance_of(described_class::Provider).to receive(:poise_shell_out!).with(%w{svccfg -s network/dns/client listprop config/nameserver}).and_return(double(stdout: "config/nameserver net_address\n"))
        expect_any_instance_of(described_class::Provider).to receive(:poise_shell_out!).with(%w{svccfg -s network/dns/client setprop config/nameserver = net_address:} + ['(8.8.8.8 8.8.4.4)'])
        run_chef
      end
    end # /context dns nameservers
  end # /context with real-world data
end
