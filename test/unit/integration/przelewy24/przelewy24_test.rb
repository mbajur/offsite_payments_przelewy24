require 'test_helper'

class Przelewy24Test < Test::Unit::TestCase
  # DIGEST = OpenSSL::Digest.new('sha256')
  def setup
    @cents       = 2995
    @merchant_id = 'MER123'
    @order_info  = '22TEST'
    @base = OffsitePayments::Integrations::Przelewy24
    @helper = @base::Helper.new(
                @order_info,
                @merchant_id,
              )
  end

  def test_make_amount
    assert_equal 1000, @base.make_amount(10)
    assert_equal 1010, @base.make_amount(10.10)
  end

  def test_helper_generate_signature
    assert_equal '90895c45555050729ed04baf40e10a47', @helper.send(:generate_signature)
  end
end
