# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join 'spec/models/concerns/reauthorizable_shared.rb'

RSpec.describe Channel::Whatsapp do
  let(:response_headers) { { 'Content-Type' => 'application/json' } }
  before do
    stub_request(:get, /subscribed_apps/)
      .to_return(status: 200, body: { 'data': [{ 'whatsapp_business_api_data': { 'link': 'https://www.facebook.com/games/?app_id=742189254309938',
                                                                                 'name': 'Baggio - 41998154704', 'id': '742189254309938' } }] }.to_json, headers: response_headers)
    stub_request(:post, /subscribed_apps/)
      .to_return(status: 200, body: '', headers: response_headers)
    stub_request(:post, /register/)
      .to_return(status: 200, body: '', headers: response_headers)
    stub_request(:get, %r{oauth/access_token})
      .to_return(status: 200, body: { 'access_token': '1234', expires_in: Time.current.to_i }.to_json, headers: response_headers)

    stub_request(:get, /debug_token/)
      .to_return(status: 200, body: { 'data': { 'expires_at': 10.days.from_now.to_i } }.to_json, headers: response_headers)
  end
  describe 'concerns' do
    let(:channel) { create(:channel_whatsapp) }


    before do
      stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
      stub_request(:get, 'https://waba.360dialog.io/v1/configs/templates')
    end

    it_behaves_like 'reauthorizable'

    context 'when prompt_reauthorization!' do
      it 'calls channel notifier mail for whatsapp' do
        admin_mailer = double
        mailer_double = double

        expect(AdministratorNotifications::ChannelNotificationsMailer).to receive(:with).and_return(admin_mailer)
        expect(admin_mailer).to receive(:whatsapp_disconnect).with(channel.inbox).and_return(mailer_double)
        expect(mailer_double).to receive(:deliver_later)

        channel.prompt_reauthorization!
      end
    end
  end

  describe 'validate_provider_config' do
    let(:channel) { build(:channel_whatsapp, provider: 'whatsapp_cloud', account: create(:account)) }

    it 'validates false when provider config is wrong' do
      stub_request(:get, 'https://graph.facebook.com/v14.0//message_templates?access_token=test_key').to_return(status: 401)
      expect(channel.save).to be(false)
    end

    it 'validates true when provider config is right' do
      stub_request(:get, /message_templates/)
        .to_return(status: 200,
                   body: { data: [{
                     id: '123456789', name: 'test_template'
                   }] }.to_json)
                   stub_request(:get, /random_id/).to_return(status: 200, body: '', headers: response_headers)
      
      expect(channel.save).to be(true)
    end
  end

  describe 'webhook_verify_token' do
    it 'generates webhook_verify_token if not present' do
      channel = create(:channel_whatsapp, provider_config: { webhook_verify_token: nil }, provider: 'whatsapp_cloud', account: create(:account),
                                          validate_provider_config: false, sync_templates: false)

      expect(channel.provider_config['webhook_verify_token']).not_to be_nil
    end

    it 'does not generate webhook_verify_token if present' do
      channel = create(:channel_whatsapp, provider: 'whatsapp_cloud', provider_config: { webhook_verify_token: '123' }, account: create(:account),
                                          validate_provider_config: false, sync_templates: false)

      expect(channel.provider_config['webhook_verify_token']).to eq '123'
    end
  end
end
