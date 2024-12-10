# == Schema Information
#
# Table name: channel_whatsapp
#
#  id                             :bigint           not null, primary key
#  message_templates              :jsonb
#  message_templates_last_updated :datetime
#  phone_number                   :string           not null
#  provider                       :string           default("default")
#  provider_config                :jsonb
#  created_at                     :datetime         not null
#  updated_at                     :datetime         not null
#  account_id                     :integer          not null
#
# Indexes
#
#  index_channel_whatsapp_on_phone_number  (phone_number) UNIQUE
#

class Channel::Whatsapp < ApplicationRecord
  include Channelable
  include Reauthorizable

  self.table_name = 'channel_whatsapp'
  EDITABLE_ATTRS = [:phone_number, :provider, { provider_config: {} }].freeze

  # default at the moment is 360dialog lets change later.
  PROVIDERS = %w[default whatsapp_cloud whatsapp_embedded].freeze
  before_validation :ensure_webhook_verify_token

  validates :provider, inclusion: { in: PROVIDERS }
  validates :phone_number, presence: true, uniqueness: true
  validate :validate_provider_config

  after_create :after_create_methods
  after_update :should_extend_token, if: :saved_change_to_provider_config?

  after_destroy :unregister_account

  def name
    'Whatsapp'
  end

  def provider_service
    if provider == 'whatsapp_cloud'
      Whatsapp::Providers::WhatsappCloudService.new(whatsapp_channel: self)
    elsif provider == 'whatsapp_embedded'
      Whatsapp::Providers::WhatsappEmbeddedService.new(whatsapp_channel: self)
    else
      Whatsapp::Providers::Whatsapp360DialogService.new(whatsapp_channel: self)
    end
  end

  def messaging_window_enabled?
    true
  end

  def mark_message_templates_updated
    # rubocop:disable Rails/SkipsModelValidations
    update_column(:message_templates_last_updated, Time.zone.now)
    # rubocop:enable Rails/SkipsModelValidations
  end

  delegate :send_message, to: :provider_service
  delegate :send_template, to: :provider_service
  delegate :sync_templates, to: :provider_service
  delegate :media_url, to: :provider_service
  delegate :api_headers, to: :provider_service

  delegate :extend_token_life, to: :provider_service
  delegate :sync_token_expiry_date, to: :provider_service
  delegate :refresh_token, to: :provider_service
  delegate :get_expires_at, to: :provider_service

  private

  def ensure_webhook_verify_token
    provider_config['webhook_verify_token'] ||= SecureRandom.hex(16) if provider == 'whatsapp_cloud' || provider == 'whatsapp_embedded'
  end

  def validate_provider_config
    errors.add(:provider_config, 'Invalid Credentials') unless provider_service.validate_provider_config?
  end
  def after_create_methods
    if(provider == 'whatsapp_embedded')
      res = self.get_expires_at
      self.extend_token_life() unless res["data"]["expires_at"] == 0
      provider_service.subscribe_app()
      provider_service.register_account()
      # provider_service.set_webhook()
      provider_service.get_app_id()
    end
    self.sync_templates()
  end

  def unregister_account
    if(provider == 'whatsapp_embedded')
      response = HTTParty.post("https://graph.facebook.com/v18.0/#{provider_config["phone_number_id"]}/deregister",
                    headers: {'Authorization' => "Bearer #{provider_config['api_key']}"}
      )
    end
  end

  def should_extend_token
    return unless provider == 'whatsapp_embedded'
    res = self.get_expires_at
    return if res["data"]["expires_at"] == 0
    return if Time.at(res["data"]["expires_at"]).utc > 7.days.after
    self.extend_token_life() if provider == 'whatsapp_embedded' && saved_changes['provider_config'][0]['api_key'] != saved_changes['provider_config'][1]['api_key']
  end
end
