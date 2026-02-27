require "test_helper"

class PortalBase::IngestDataSourceJobTest < ActiveJob::TestCase
  test "enqueues first page using checkpoint" do
    data_source = data_sources(:portal_base)
    data_source.update!(last_success_page: 4)

    assert_enqueued_with(job: PortalBase::IngestPageJob, args: [ data_source.id, 5, { page_size: 20 } ]) do
      PortalBase::IngestDataSourceJob.perform_now(data_source.id, page_size: 20)
    end
  end

  test "uses explicit start_page when provided" do
    data_source = data_sources(:portal_base)

    assert_enqueued_with(job: PortalBase::IngestPageJob, args: [ data_source.id, 2, { page_size: 15 } ]) do
      PortalBase::IngestDataSourceJob.perform_now(data_source.id, page_size: 15, start_page: 2)
    end
  end
end
