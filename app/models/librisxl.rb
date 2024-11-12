class Librisxl
  require 'pp'
  # Must be included here to work in production
  require 'rest-client'

  def self.get_token
    token_url = ENV['LIBRIS_TOKEN_URL']
    client_id = ENV['LIBRIS_CLIENT_ID']
    client_secret = ENV['LIBRIS_CLIENT_SECRET']
    response = RestClient.post token_url, {client_id: client_id, client_secret: client_secret, grant_type: 'client_credentials'}

    # If response status is 200, return the json attribute access_token in the response body
    if response.code == 200
      return JSON.parse(response.body)['access_token']
    else
      return nil
    end
  end

  def self.get_libris_xl_id id
    # TBD
  end

  def self.get_record id
    libris_url = ENV['LIBRIS_BASE_URL']
    pp libris_url
    response = RestClient.get "#{libris_url}/#{id}", {accept: 'application/ld+json'}
    if response.code == 200
      return JSON.parse(response.body)
    else
      return nil
    end
  end

  def self.write_record token, data
    libris_url = ENV['LIBRIS_BASE_URL'] + "/data"
    header = {content_type: 'application/ld+json', authorization: "Bearer #{token}", xl_active_sigel: ENV['SIGEL']}
    begin
      response = RestClient.post libris_url, data.to_json, header
    rescue RestClient::ExceptionWithResponse => e
      response = e.response
    end
    # If response status is 201, return the new record id thar can be found in the Location header
    if response.code == 201
      return response.headers[:location].split('/').last
    else
      return nil
    end
  end

end