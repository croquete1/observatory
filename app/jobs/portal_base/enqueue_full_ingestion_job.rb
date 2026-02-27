# :nocov:
# frozen_string_literal: true

module PortalBase
  class EnqueueFullIngestionJob < ApplicationJob
    queue_as :portal_base_ingestion

    def perform(page_size: ENV.fetch("PORTAL_BASE_PAGE_SIZE", 100).to_i)
      DataSource.active_sources.portal_base.find_each do |data_source|
        IngestDataSourceJob.perform_later(data_source.id, page_size: page_size)
      end
    end
  end
end

# :nocov:
