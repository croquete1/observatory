require "test_helper"

class FlagTest < ActiveSupport::TestCase
  test "valid flag" do
    flag = Flag.new(
      contract: contracts(:one),
      flag_key: "A2_DATE_ANOMALY",
      severity: "high",
      confidence: 0.9,
      data_completeness: 0.75,
      fingerprint: "abc123",
      evidence: { publication_date: "2026-02-01" }
    )

    assert flag.valid?
  end

  test "invalid without required fields" do
    flag = Flag.new

    assert_not flag.valid?
    assert_includes flag.errors[:contract], "must exist"
    assert_includes flag.errors[:flag_key], "can't be blank"
    assert_includes flag.errors[:severity], "can't be blank"
    assert_includes flag.errors[:fingerprint], "can't be blank"
  end

  test "severity must be from allowlist" do
    flag = Flag.new(
      contract: contracts(:one),
      flag_key: "A2_DATE_ANOMALY",
      severity: "critical",
      confidence: 0.9,
      data_completeness: 0.75,
      fingerprint: "abc123"
    )

    assert_not flag.valid?
    assert_includes flag.errors[:severity], "is not included in the list"
  end

  test "confidence and data completeness must be between 0 and 1" do
    flag = Flag.new(
      contract: contracts(:one),
      flag_key: "A2_DATE_ANOMALY",
      severity: "high",
      confidence: 1.1,
      data_completeness: -0.1,
      fingerprint: "abc123"
    )

    assert_not flag.valid?
    assert_includes flag.errors[:confidence], "must be less than or equal to 1"
    assert_includes flag.errors[:data_completeness], "must be greater than or equal to 0"
  end

  test "country_code is synchronized from contract" do
    flag = Flag.create!(
      contract: contracts(:three),
      flag_key: "A2_DATE_ANOMALY",
      severity: "medium",
      confidence: 0.8,
      data_completeness: 1.0,
      fingerprint: "es-fingerprint"
    )

    assert_equal "ES", flag.country_code
  end

  test "country mismatch validation is enforced when sync callback is disabled" do
    Flag.skip_callback(:validation, :before, :sync_country_code_from_contract)

    flag = Flag.new(
      contract: contracts(:one),
      country_code: "ES",
      flag_key: "A2_DATE_ANOMALY",
      severity: "medium",
      confidence: 0.8,
      data_completeness: 1.0,
      fingerprint: "mismatch-fingerprint"
    )

    assert_not flag.valid?
    assert_includes flag.errors[:country_code], "must match the associated contract country"
  ensure
    Flag.set_callback(:validation, :before, :sync_country_code_from_contract)
  end



  test "upsert_for_service retries on record not unique" do
    contract = contracts(:one)
    attributes = {
      contract_id: contract.id,
      country_code: contract.country_code,
      flag_key: "A3_EXECUTION_BEFORE_PUBLICATION",
      severity: "high",
      confidence: 0.8,
      data_completeness: 1.0,
      evidence: { anomaly: true },
      fingerprint: "retry-fingerprint",
      detected_at: Time.current
    }

    calls = 0
    original = Flag.method(:find_or_initialize_by)

    Flag.stub(:find_or_initialize_by, lambda { |**kwargs|
      calls += 1
      raise ActiveRecord::RecordNotUnique if calls == 1

      original.call(**kwargs)
    }) do
      result = Flag.upsert_for_service!(attributes)
      assert_equal :created, result
    end

    assert_equal 2, calls
  end

  test "database unique index blocks duplicate per contract and flag key" do
    contract = contracts(:one)
    now = Time.current

    Flag.insert_all!([
      {
        contract_id: contract.id,
        country_code: contract.country_code,
        flag_key: "A2_DATE_ANOMALY",
        severity: "medium",
        confidence: 0.8,
        data_completeness: 1.0,
        evidence: {},
        fingerprint: "fp-1",
        detected_at: now,
        created_at: now,
        updated_at: now
      }
    ])

    assert_raises ActiveRecord::RecordNotUnique do
      Flag.insert_all!([
        {
          contract_id: contract.id,
          country_code: contract.country_code,
          flag_key: "A2_DATE_ANOMALY",
          severity: "medium",
          confidence: 0.8,
          data_completeness: 1.0,
          evidence: {},
          fingerprint: "fp-2",
          detected_at: now,
          created_at: now,
          updated_at: now
        }
      ])
    end
  end
end
