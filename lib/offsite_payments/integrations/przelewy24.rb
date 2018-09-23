module OffsitePayments
  module Integrations
    module Przelewy24
      mattr_accessor :test_url
      self.test_url = 'https://sandbox.przelewy24.pl/trnDirect'

      mattr_accessor :production_url
      self.production_url = 'https://secure.przelewy24.pl/trnDirect'

      mattr_accessor :test_verification_url
      self.test_verification_url = 'https://sandbox.przelewy24.pl/trnVerify'

      mattr_accessor :production_verification_url
      self.production_verification_url = 'https://secure.przelewy24.pl/trnVerify'

      def self.service_url
        mode = OffsitePayments.mode

        case mode
        when :production
          self.production_url
        when :test
          self.test_url
        else
          raise StandardError, "Integration mode set to an invalid value: #{mode}"
        end
      end

      def self.verification_url
        mode = OffsitePayments.mode

        case mode
        when :production
          self.production_verification_url
        when :test
          self.test_verification_url
        else
          raise StandardError, "Integration mode set to an invalid value: #{mode}"
        end
      end

      def self.make_amount(price)
        price.present? ? (price.to_f.round(2) * 100).to_i : 0
      end

      def self.notification(post, options = {})
        Notification.new(post, options)
      end

      def self.return(query_string, options = {})
        Return.new(query_string)
      end

      class Helper < OffsitePayments::Helper
        def initialize(order, account, options = {})
          @crc_key = options.delete(:credential2)
          super

          add_field 'p24_api_version', '3.2'
          add_field 'p24_session_id', order
        end

        mapping :account, ['p24_merchant_id', 'p24_pos_id']
        mapping :amount, 'p24_amount'
        mapping :currency, 'p24_currency'
        mapping :description, 'p24_description'
        mapping :notify_url, 'p24_url_status'
        mapping :return_url, 'p24_url_return'

        def customer(params = {})
          add_field 'p24_client', "#{params[:first_name]} #{params[:last_name]}"
          add_field 'p24_email', params[:email]
        end

        def form_fields
          @fields['p24_amount'] = Przelewy24.make_amount(@fields['p24_amount'])
          @fields['p24_currency'] = @fields['p24_currency'].upcase

          @fields.merge(
            p24_sign: generate_signature
          )
        end

        private

        def generate_signature
          Digest::MD5.hexdigest([
            @fields['p24_session_id'].to_s,
            @fields['p24_merchant_id'].to_s,
            @fields['p24_amount'].to_s,
            @fields['p24_currency'].to_s,
            @crc_key.to_s
          ].join('|'))
        end
      end

      class Notification < OffsitePayments::Notification
        include ActiveUtils::PostsData

        def self.recognizes?(params)
          params.key?('p24_session_id') && params.key?('p24_amount')
        end

        def initialize(post, options = {})
          raise ArgumentError if post.blank?
          super
        end

        def complete?
          !params['error'].present?
        end

        def account
          params['p24_merchant_id']
        end

        def pos_id
          params['p24_pos_id']
        end

        def amount
          params['p24_amount']
        end

        def item_id
          params['p24_session_id']
        end

        def transaction_id
          params['p24_order_id']
        end

        def currency
          params['p24_currency']
        end

        def method
          params['p24_method']
        end

        def statement
          params['p24_statement']
        end

        def security_key
          params['p24_sign']
        end

        def acknowledge(_authcode = nil)
          payload = {
            p24_merchant_id: params['p24_merchant_id'],
            p24_pos_id: params['p24_pos_id'],
            p24_session_id: params['p24_session_id'],
            p24_amount: params['p24_amount'],
            p24_currency: params['p24_currency'],
            p24_order_id: params['p24_order_id']
          }

          payload[:p24_sign] = verify_sign(payload)

          response = ssl_post(Przelewy24.verification_url, parameterize(payload),
            'User-Agent' => 'Active Merchant -- http://activemerchant.org'
          )
          parsed_response = parse_response(response)
          parsed_response.error == '0'
        end

        private

        def parameterize(params)
          params.reject { |k, v| v.blank? }.keys.sort.collect { |key| "#{key}=#{CGI.escape(params[key].to_s)}" }.join("&")
        end

        ## P24 Error codes
        # err00: Incorrect call
        # err01: Authorization answer confirmation was not received.
        # err02: Authorization answer was not received.
        # err03: This query has been already processed.
        # err04: Authorization query incomplete or incorrect.
        # err05: Store configuration cannot be read.
        # err06: Saving of authorization query failed.
        # err07: Another payment is being concluded.
        # err08: Undetermined store connection status.
        # err09: Permitted corrections amount has been exceeded.
        # err10: Incorrect transaction value!
        # err49: To high transaction risk factor.
        # err51: Incorrect reference method.
        # err52: Incorrect feedback on session information!
        # err53: Transaction error !: err54: Incorrect transaction value!
        # err55: Incorrect transaction id!
        # err56: Incorrect card
        # err57: Incompatibility of TEST flag
        # err58: Incorrect sequence number !
        # err101: Incorrect call
        # err102: Allowed transaction time has expired
        # err103: Incorrect transfer value.
        # err104: Transaction awaits confirmation.
        # err105: Transaction finished after allowed time.
        # err106: Transaction result verification error
        # err161: Transaction request terminated by user
        # err162: Transaction request terminated by user
        def parse_response(response)
          ret = OpenStruct.new
          response.split('&').each do |arg|
            line = arg.split('=')
            ret[line[0].strip] = line[1].force_encoding('ISO-8859-2').encode!('UTF-8')
          end
          ret
        end

        def verify_sign(payload)
          Digest::MD5.hexdigest([
            payload[:p24_session_id],
            payload[:p24_order_id],
            Przelewy24.make_amount(payload[:p24_amount]),
            payload[:p24_currency],
            @options[:credential2]
          ].join('|'))
        end
      end

      class Return < OffsitePayments::Return
      end
    end
  end
end
