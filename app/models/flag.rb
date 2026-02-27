class Flag < ApplicationRecord
  SEVERITIES = %w[low medium high].freeze

  belongs_to :contract

  validates :contract_id, :country_code, :flag_key, :severity, :fingerprint, :detected_at, presence: true
  validates :flag_key, uniqueness: { scope: :contract_id }
  validates :severity, inclusion: { in: SEVERITIES }
  validates :confidence, :data_completeness,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  validates :country_code,
            format: {
              with: /\A[A-Z]{2}\z/,
              message: "must be a 2-letter ISO 3166-1 alpha-2 code (e.g. PT, ES)"
            }

  before_validation :sync_country_code_from_contract
  before_validation :default_detected_at

  validate :contract_country_code_must_match

  def self.upsert_for_service!(attributes)
    contract_id = attributes.fetch(:contract_id)
    flag_key = attributes.fetch(:flag_key)

    record = find_or_initialize_by(contract_id:, flag_key:)
    created = record.new_record?
    record.assign_attributes(attributes)
    record.save!

    created ? :created : :updated
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  private

  def sync_country_code_from_contract
    self.country_code = contract&.country_code if contract_id.present?
  end

  def default_detected_at
    self.detected_at ||= Time.current
  end

  def contract_country_code_must_match
    return if contract.nil? || country_code.blank?
    return if contract.country_code == country_code

    errors.add(:country_code, "must match the associated contract country")
  end
end
