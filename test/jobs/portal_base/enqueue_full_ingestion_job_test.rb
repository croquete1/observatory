require "test_helper"

class PortalBase::EnqueueFullIngestionJobTest < ActiveJob::TestCase
  test "enqueues one job per active portal base data source" do
    assert_enqueued_jobs 2, only: PortalBase::IngestDataSourceJob do
      PortalBase::EnqueueFullIngestionJob.perform_now(page_size: 25)
    end
  end
end
