class ApplicationController < ActionController::API
  private
  # Validates given api_key against configurated key
  def validate_key_access service
    api_key_provided = params[:api_key]
    if !api_key_provided
      render status: :unauthorized, json: {error: {msg: "Api key is missing"}}
      return
    end
    # Get the api key from the configuration
    api_key_configurated = ENV["#{service}_API_KEY"]
    if api_key_provided != api_key_configurated
      render status: :unauthorized, json: {error: {msg: "Api key is not valid"}}
      return
    end
  end 
end
