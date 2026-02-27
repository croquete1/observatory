# :nocov:
# frozen_string_literal: true

module PortalBase
  class IngestPageJob < ApplicationJob
    queue_as :portal_base_ingestion

    retry_on PublicContracts::PT::PortalBaseClient::TransientError,
             wait: :polynomially_longer,
             attempts: ENV.fetch("PORTAL_BASE_MAX_RETRIES", 5).to_i

    retry_on Net::OpenTimeout, Net::ReadTimeout,
             wait: :polynomially_longer,
             attempts: ENV.fetch("PORTAL_BASE_MAX_RETRIES", 5).to_i

    discard_on ActiveRecord::RecordNotFound

    CIRCUIT_BREAKER_FAILURE_THRESHOLD = ENV.fetch("PORTAL_BASE_CIRCUIT_BREAKER_FAILURE_THRESHOLD", 5).to_i

    def perform(data_source_id, page, page_size: ENV.fetch("PORTAL_BASE_PAGE_SIZE", 100).to_i)
      data_source = DataSource.find(data_source_id)
      result = PublicContracts::ImportService.new(data_source).call(page: page, page_size: page_size)

      reset_failure_counter(data_source)
      sleep(rate_limit_sleep_seconds) if rate_limit_sleep_seconds.positive?

      return unless result[:fetched] >= page_size

      self.class.perform_later(data_source.id, page + 1, page_size: page_size)
    rescue PublicContracts::PT::PortalBaseClient::TransientError, Net::OpenTimeout, Net::ReadTimeout => e
      failures = increment_failure_counter(data_source_id)
      Rails.logger.warn({ event: "portal_base.ingest_retry", data_source_id: data_source_id, page: page, failures: failures,
                          error: e.message }.to_json)

      if failures >= CIRCUIT_BREAKER_FAILURE_THRESHOLD
        DataSource.where(id: data_source_id).update_all(status: DataSource.statuses[:error])
        raise StandardError, "Portal BASE circuit breaker opened for DataSource ##{data_source_id}"
      end

      raise
    end

    private

    def rate_limit_sleep_seconds
      ENV.fetch("PORTAL_BASE_PAGE_SLEEP_SECONDS", 0.1).to_f
    end

    def cache_key(data_source_id)
      "portal_base:ingest:failures:#{data_source_id}"
    end

    def increment_failure_counter(data_source_id)
      Rails.cache.increment(cache_key(data_source_id), 1, initial: 0, expires_in: 30.minutes)
    end

    def reset_failure_counter(data_source)
      Rails.cache.delete(cache_key(data_source.id))
    end
  end
end

# :nocov:
