# :nocov:
# frozen_string_literal: true

module PublicContracts
  class ImportService
    DEFAULT_PAGE_SIZE = 50

    def initialize(data_source_record, logger: Rails.logger)
      @ds = data_source_record
      @logger = logger
    end

    def call(page: 1, page_size: DEFAULT_PAGE_SIZE, full: false, start_page: nil)
      return import_full(page_size: page_size, start_page: start_page || page) if full

      import_page(page: page, page_size: page_size)
    rescue StandardError
      @ds.update!(status: :error)
      raise
    end

    private

    def import_full(page_size:, start_page: 1)
      current_page = [ start_page.to_i, 1 ].max
      totals = empty_result.merge(start_page: current_page)

      loop do
        page_result = import_page(page: current_page, page_size: page_size)
        merge!(totals, page_result)
        break if page_result[:fetched].zero?

        current_page += 1
      end

      totals
    end

    def import_page(page:, page_size:)
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      contracts = Array(@ds.adapter.fetch_contracts(page: page, limit: page_size))
      result = empty_result.merge(page: page, page_size: page_size, fetched: contracts.size)

      contracts.each do |attrs|
        contract_result = import_contract(attrs)
        result[:inserted] += 1 if contract_result == :inserted
        result[:updated] += 1 if contract_result == :updated
      rescue StandardError => e
        result[:failed] += 1
        structured_log(event: "portal_base.contract_failed", page: page, external_id: attrs["external_id"], error: e.message)
      end

      @ds.update!(
        status: :active,
        last_synced_at: Time.current,
        record_count: Contract.where(data_source_id: @ds.id).count,
        last_success_page: [ @ds.last_success_page.to_i, page.to_i ].max
      )

      structured_log(
        event: "portal_base.page_imported",
        data_source_id: @ds.id,
        page: page,
        page_size: page_size,
        fetched: result[:fetched],
        inserted: result[:inserted],
        updated: result[:updated],
        failed: result[:failed],
        duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
      )

      result
    end

    def import_contract(attrs)
      country_code = attrs["country_code"].presence || @ds.country_code
      return :skipped if attrs["external_id"].blank? || country_code.blank?

      contracting = find_or_create_entity(
        attrs.dig("contracting_entity", "tax_identifier"),
        attrs.dig("contracting_entity", "name"),
        is_public_body: attrs.dig("contracting_entity", "is_public_body") || false
      )
      return :skipped unless contracting

      contract = Contract.find_or_initialize_by(
        external_id: attrs["external_id"],
        country_code: country_code
      )

      is_new = contract.new_record?
      contract.assign_attributes(
        object: attrs["object"],
        contract_type: attrs["contract_type"],
        procedure_type: attrs["procedure_type"],
        publication_date: attrs["publication_date"],
        celebration_date: attrs["celebration_date"],
        base_price: attrs["base_price"],
        total_effective_price: attrs["total_effective_price"],
        cpv_code: attrs["cpv_code"],
        location: attrs["location"],
        contracting_entity: contracting,
        data_source: @ds
      )

      contract.save!
      upsert_winners(contract, attrs)

      is_new ? :inserted : :updated
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    def upsert_winners(contract, attrs)
      Array(attrs["winners"]).each do |winner_attrs|
        winner = find_or_create_entity(
          winner_attrs["tax_identifier"],
          winner_attrs["name"],
          is_company: winner_attrs["is_company"] || false
        )
        next unless winner

        ContractWinner.find_or_create_by!(contract: contract, entity: winner)
      rescue ActiveRecord::RecordNotUnique
        retry
      end
    end

    def find_or_create_entity(tax_id, name, is_public_body: false, is_company: false)
      return nil if tax_id.blank? || name.blank?

      entity = Entity.find_or_initialize_by(tax_identifier: tax_id, country_code: @ds.country_code)
      entity.assign_attributes(name: name, is_public_body: is_public_body, is_company: is_company)
      entity.save!
      entity
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    def empty_result
      { fetched: 0, inserted: 0, updated: 0, failed: 0 }
    end

    def merge!(totals, page_result)
      totals[:fetched] += page_result[:fetched]
      totals[:inserted] += page_result[:inserted]
      totals[:updated] += page_result[:updated]
      totals[:failed] += page_result[:failed]
    end

    def structured_log(payload)
      @logger.info(payload.to_json)
    end
  end
end

# :nocov:
