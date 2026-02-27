# :nocov:
# frozen_string_literal: true

module PortalBase
  class IngestDataSourceJob < ApplicationJob
    queue_as :portal_base_ingestion

    def perform(data_source_id, page_size: ENV.fetch("PORTAL_BASE_PAGE_SIZE", 100).to_i, start_page: nil)
      data_source = DataSource.find(data_source_id)
      first_page = start_page.presence || data_source.last_success_page.to_i + 1
      first_page = 1 if first_page.to_i < 1

      IngestPageJob.perform_later(data_source.id, first_page.to_i, page_size: page_size)
    end
  end
end

# :nocov:
