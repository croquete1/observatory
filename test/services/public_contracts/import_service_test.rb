require "test_helper"

class PublicContracts::ImportServiceTest < ActiveSupport::TestCase
  FakeAdapter = Struct.new(:pages) do
    def fetch_contracts(page:, limit:)
      _ = limit
      pages.fetch(page, [])
    end
  end

  def build_contract_attrs(overrides = {})
    {
      "external_id"   => "ext-#{SecureRandom.hex(4)}",
      "object"        => "Serviços de consultoria",
      "country_code"  => "PT",
      "contract_type" => "Aquisição de Serviços",
      "procedure_type" => "Ajuste direto",
      "publication_date" => Date.current,
      "base_price"    => 15000.0,
      "contracting_entity" => {
        "tax_identifier" => "500000001",
        "name"           => "Câmara Municipal Teste",
        "is_public_body" => true
      },
      "winners" => [
        { "tax_identifier" => "509888001", "name" => "Empresa Vencedora Lda", "is_company" => true }
      ]
    }.merge(overrides)
  end

  test "call imports one page and updates counters" do
    attrs = build_contract_attrs
    ds = data_sources(:portal_base)
    ds.stub(:adapter, FakeAdapter.new({ 2 => [ attrs ] })) do
      result = PublicContracts::ImportService.new(ds).call(page: 2, page_size: 10)
      assert_equal 1, result[:fetched]
      assert_equal 1, result[:inserted]
      assert_equal 0, result[:failed]
    end

    ds.reload
    assert_equal 2, ds.last_success_page
    assert ds.active?
    assert_equal Contract.where(data_source_id: ds.id).count, ds.record_count
  end

  test "full mode paginates until empty page" do
    attrs = build_contract_attrs
    ds = data_sources(:portal_base)
    ds.stub(:adapter, FakeAdapter.new({ 1 => [ attrs ], 2 => [] })) do
      result = PublicContracts::ImportService.new(ds).call(full: true, page_size: 5)
      assert_equal 1, result[:fetched]
      assert_equal 1, result[:inserted]
      assert_equal 0, result[:failed]
    end
  end

  test "full mode accepts start_page" do
    attrs = build_contract_attrs
    ds = data_sources(:portal_base)
    ds.stub(:adapter, FakeAdapter.new({ 3 => [ attrs ], 4 => [] })) do
      result = PublicContracts::ImportService.new(ds).call(full: true, page_size: 5, start_page: 3)
      assert_equal 3, result[:start_page]
      assert_equal 1, result[:inserted]
    end
  end

  test "call creates contracting entity winner and join row" do
    attrs = build_contract_attrs
    ds = data_sources(:portal_base)

    ds.stub(:adapter, FakeAdapter.new({ 1 => [ attrs ] })) do
      assert_difference "Contract.count", 1 do
        assert_difference "Entity.count", 2 do
          assert_difference "ContractWinner.count", 1 do
            PublicContracts::ImportService.new(ds).call(page: 1, page_size: 50)
          end
        end
      end
    end
  end

  test "call falls back to data_source country_code when attrs country_code missing" do
    attrs = build_contract_attrs.tap { |contract| contract.delete("country_code") }
    ds = data_sources(:portal_base)

    ds.stub(:adapter, FakeAdapter.new({ 1 => [ attrs ] })) do
      PublicContracts::ImportService.new(ds).call(page: 1, page_size: 50)
    end

    contract = Contract.find_by!(external_id: attrs["external_id"])
    assert_equal "PT", contract.country_code
  end

  test "two executions with same external id do not duplicate and update mutable fields" do
    attrs = build_contract_attrs("external_id" => "same-contract", "object" => "Original")
    ds = data_sources(:portal_base)

    ds.stub(:adapter, FakeAdapter.new({ 1 => [ attrs ] })) do
      PublicContracts::ImportService.new(ds).call(page: 1, page_size: 50)
    end

    updated_attrs = attrs.merge("object" => "Updated")
    ds.stub(:adapter, FakeAdapter.new({ 1 => [ updated_attrs ] })) do
      assert_no_difference "Contract.count" do
        result = PublicContracts::ImportService.new(ds).call(page: 1, page_size: 50)
        assert_equal 1, result[:updated]
      end
    end

    assert_equal "Updated", Contract.find_by!(external_id: "same-contract").object
  end

  test "call skips contract when contracting entity is invalid" do
    attrs = build_contract_attrs("contracting_entity" => { "tax_identifier" => "", "name" => "" })
    ds = data_sources(:portal_base)

    ds.stub(:adapter, FakeAdapter.new({ 1 => [ attrs ] })) do
      assert_no_difference "Contract.count" do
        result = PublicContracts::ImportService.new(ds).call(page: 1, page_size: 50)
        assert_equal 0, result[:inserted]
      end
    end
  end

  test "call skips winner when winner identity is invalid" do
    attrs = build_contract_attrs("winners" => [ { "tax_identifier" => "", "name" => "No ID" } ])
    ds = data_sources(:portal_base)

    ds.stub(:adapter, FakeAdapter.new({ 1 => [ attrs ] })) do
      assert_no_difference "ContractWinner.count" do
        PublicContracts::ImportService.new(ds).call(page: 1, page_size: 50)
      end
    end
  end

  test "call counts failed contracts within a page and continues" do
    valid = build_contract_attrs("external_id" => "ok-1")
    invalid = build_contract_attrs("external_id" => "bad-1", "object" => nil)
    ds = data_sources(:portal_base)

    ds.stub(:adapter, FakeAdapter.new({ 1 => [ valid, invalid ] })) do
      result = PublicContracts::ImportService.new(ds).call(page: 1, page_size: 50)
      assert_equal 2, result[:fetched]
      assert_equal 1, result[:inserted]
      assert_equal 1, result[:failed]
    end
  end

  test "call sets status to error when adapter raises" do
    adapter = Object.new
    def adapter.fetch_contracts(page:, limit:)
      _ = page
      _ = limit
      raise RuntimeError, "API down"
    end

    ds = data_sources(:portal_base)
    ds.stub(:adapter, adapter) do
      assert_raises(RuntimeError) do
        PublicContracts::ImportService.new(ds).call(page: 1, page_size: 50)
      end
    end

    assert ds.reload.error?
  end
end
