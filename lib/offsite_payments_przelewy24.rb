module OffsitePaymentsPrzelewy24
  require 'offsite_payments'
  require_relative 'offsite_payments/integrations/przelewy24'

  mattr_accessor :mode
  self.mode = :production

  # A check to see if we're in test mode
  def self.test?
    self.mode == :test
  end
end
