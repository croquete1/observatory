require "test_helper"

class PortalBase::IngestPageJobTest < ActiveJob::TestCase
  test "imports page and enqueues next when page is full" do
    data_source = data_sources(:portal_base)
    service = Object.new
    service.define_singleton_method(:call) do |page:, page_size:|
      raise "unexpected page" unless page == 3
      raise "unexpected page size" unless page_size == 10
      { fetched: 10, inserted: 7, updated: 3, failed: 0 }
    end

    PublicContracts::ImportService.stub(:new, ->(_ds) { service }) do
      assert_enqueued_with(job: PortalBase::IngestPageJob, args: [ data_source.id, 4, { page_size: 10 } ]) do
        PortalBase::IngestPageJob.perform_now(data_source.id, 3, page_size: 10)
      end
    end
  end

  test "does not enqueue next page when empty" do
    data_source = data_sources(:portal_base)
    service = Object.new
    service.define_singleton_method(:call) do |page:, page_size:|
      raise "unexpected page" unless page == 8
      raise "unexpected page size" unless page_size == 10
      { fetched: 0, inserted: 0, updated: 0, failed: 0 }
    end

    PublicContracts::ImportService.stub(:new, ->(_ds) { service }) do
      assert_no_enqueued_jobs only: PortalBase::IngestPageJob do
        PortalBase::IngestPageJob.perform_now(data_source.id, 8, page_size: 10)
      end
    end
  end
end
