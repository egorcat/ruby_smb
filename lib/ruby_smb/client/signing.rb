module RubySMB
  class Client
    # Contains the methods for handling packet signing
    module Signing
      # The NTLM Session Key used for signing
      # @!attribute [rw] session_key
      #   @return [String]
      attr_accessor :session_key

      # Take an SMB1 packet and checks to see if it should be signed.
      # If signing is enabled and we have a session key already, then
      # it will sign the packet appropriately.
      #
      # @param packet [RubySMB::GenericPacket] the packet to sign
      # @return [RubySMB::GenericPacket] the packet, signed if needed
      def smb1_sign(packet)
        if signing_required && !session_key.empty?
          # Pack the Sequence counter into a int64le
          packed_sequence_counter = [sequence_counter].pack('Q<')
          packet.smb_header.security_features = packed_sequence_counter
          signature = OpenSSL::Digest::MD5.digest(session_key + packet.to_binary_s)[0, 8]
          packet.smb_header.security_features = signature
          self.sequence_counter += 1
        end
        packet
      end

      # Take an SMB2 packet and checks to see if it should be signed.
      # If signing is enabled and we have a session key already, then
      # it will sign the packet appropriately.
      #
      # @param packet [RubySMB::GenericPacket] the packet to sign
      # @return [RubySMB::GenericPacket] the packet, signed if needed
      def smb2_sign(packet)
        if signing_required && !session_key.empty?
          packet.smb2_header.flags.signed = 1
          packet.smb2_header.signature = "\x00" * 16
          hmac = OpenSSL::HMAC.digest(OpenSSL::Digest::SHA256.new, session_key, packet.to_binary_s)
          packet.smb2_header.signature = hmac[0, 16]
        end
        packet
      end

      def smb3_sign(packet)
        if !session_key.empty? && (signing_required || packet.is_a?(RubySMB::SMB2::Packet::TreeConnectRequest))
          case @dialect
          when '0x0300', '0x0302'
            signing_key = RubySMB::Crypto::KDF.counter_mode(@session_key, "SMB2AESCMAC\x00", "SmbSign\x00")
          when '0x0311'
            signing_key = RubySMB::Crypto::KDF.counter_mode(@session_key, "SMBSigningKey\x00", @preauth_integrity_hash_value)
          else
            raise RubySMB::Error::SigningError.new('Dialect is incompatible with SMBv3 signing')
          end

          packet.smb2_header.flags.signed = 1
          packet.smb2_header.signature = "\x00" * 16
          hmac = OpenSSL::CMAC.digest('AES', signing_key, packet.to_binary_s)
          packet.smb2_header.signature = hmac[0, 16]
        end
        packet
      end
    end
  end
end
