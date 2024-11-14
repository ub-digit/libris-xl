class LibrisxlApi
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
    # If the id numerical and shorter than 12 characters, it is not a Libris XL id and we must search for it
    if id.to_i.to_s == id && id.length < 12
      return search_libris_xl_id id
    else
      # TBD Check if the id is a valid Libris XL id?
      return id
    end
  end

  def self.search_libris_xl_id id
    libris_api_base_url = ENV['LIBRIS_API_BASE_URL']
    libris_resource_base_url = ENV['LIBRIS_RESOURCE_BASE_URL']
    response = RestClient.get "#{libris_api_base_url}/find?sameAs.@id=#{libris_resource_base_url}/#{id}", {accept: 'application/ld+json'}
    if response.code == 200
      data = JSON.parse(response.body)
      # If "totalItems": is not 1, return nil
      if data["totalItems"] != 1
        return nil
      end
      # Get @id from the only object in the items array
      libris_xl_id =  data["items"][0]["@id"].split('/').last
      # if id ends with #it, remove it
      if libris_xl_id.end_with? "#it"
        libris_xl_id = libris_xl_id[0..-4]
      end
      return libris_xl_id
    else
      return nil
    end
  end

  def self.get_record id
    libris_api_base_url = ENV['LIBRIS_API_BASE_URL']
    response = RestClient.get "#{libris_api_base_url}/#{id}", {accept: 'application/ld+json'}
    if response.code == 200
      return JSON.parse(response.body)
    else
      return nil
    end
  end

  def self.write_record token, data
    libris_api_base_url = ENV['LIBRIS_API_BASE_URL'] + "/data"
    header = {content_type: 'application/ld+json', authorization: "Bearer #{token}", xl_active_sigel: ENV['SIGEL']}
    begin
      response = RestClient.post libris_api_base_url, data.to_json, header
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