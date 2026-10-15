# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # Personal data (R15): identity fields, chat text, uploads and transcripts. Partial matches,
  # so `name` also covers `full_name` and `message` covers `messages`.
  :name, :dob, :date_of_birth, :address, :phone, :message, :content, :image, :file, :transcript
]
