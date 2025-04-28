class DflowController < ApplicationController
  # call validate_key_access before the create action
  before_action only: [:create] do
    validate_key_access("DFLOW")
  end

  # POST /dflow/create
  def create
    # Remove all keys in params with empty values
    params[:record].delete_if { |k, v| v.blank? }

    # Trim all values in params
    params[:record].transform_values!(&:strip)

    if !params[:record]
      render status: :bad_request, json: {error: {msg: "Missing record object as parameter"}}
      return
    end

    # Following parameters are recieved from the dFlow, and are mandatory
    libris_id = params[:record][:libris_id]
    url = params[:record][:url]
    # If not present, the request will be rejected
    if !libris_id || !url
      render status: :bad_request, json: {error: {msg: "Missing libris_id or url"}}
      return
    end

    # Get a valid libris xl id from the libris id
    libris_xl_id = LibrisxlApi.get_libris_xl_id(libris_id)
    if !libris_xl_id
      render status: :bad_request, json: {error: {msg: "Failed to get Libris XL id"}}
      return
    end

    # Following parameters are not mandatory, if not present they will be added from environment variables
    # type
    # place
    # agency (agent)
    # publicnote
    # remark
    # publicnote_holding
    # remark_holding
    # bibliographic_code
    # additional_bibliographic_code
    type = params[:record][:type] || ENV["TYPE"]
    place = params[:record][:place] || ENV["PLACE"]
    agent = params[:record][:agency] || params[:record][:agent] || ENV["AGENT"] # agency is a typo in the dFlow
    publicnote = params[:record][:publicnote] || ENV["PUBLICNOTE"]
    remark = params[:record][:remark] || ENV["REMARK"]
    publicnote_holding = params[:record][:publicnote_holding] || ENV["PUBLICNOTE_HOLDING"]
    remark_holding = params[:record][:remark_holding] || ENV["REMARK_HOLDING"]
    bibliographic_code = params[:record][:bibliographic_code] || ENV["BIBLIOGRAPHIC_CODE"]
    additional_bibliographic_code = params[:record][:additional_bibliographic_code] || ENV["ADDITIONAL_BIBLIOGRAPHIC_CODE"]

    # For testing and debugging
    dry_run = params[:test] || false

    original_record = LibrisxlApi.get_record(libris_xl_id)
    if !original_record
      render status: :internal_server_error, json: {error: {msg: "Failed to get record"}}
      return
    end

    begin
      # Create reproductionOf object
      reproduction_of = create_reproduction_of(libris_xl_id)
      # Get bibliographic codes from the record and store them in an array
      bibliographic_codes = [bibliographic_code, additional_bibliographic_code].compact.reject(&:empty?)
      # Create bibligraphy object
      bibliography = create_bibliography(bibliographic_codes)

      # Get issuanceType from the record
      issuanceType = create_issuance_type(original_record)

      # Create hasTitle object
      has_title = create_has_title(original_record)

      # Create instanceOf object
      instance_of = create_instance_of(original_record)

      # Create associatedMedia object
      associated_media = create_associated_media(url, publicnote, remark)

      # create production object
      production = create_production(place, agent, type)
    # If there is a raise error, return a 400 bad request
    rescue => e
      render status: :bad_request, json: {error: {msg: "Error in creating data from the libris record #{libris_id}: #{e.message}"}}
      return
    end


    # Create electronic record object
    electronic_record = create_electronic_record(reproduction_of, bibliography, issuanceType, has_title, instance_of, associated_media, production)

    token = LibrisxlApi.get_token
    if !token
      render status: :internal_server_error, json: {error: {msg: "Failed to get token"}}
      return
    end

    # Write the record to Libris XL
    if dry_run
      electronic_record_id = "test_electronic_id"
    else
      electronic_record_id = LibrisxlApi.write_record(token, electronic_record)
      if !electronic_record_id
        render status: :internal_server_error, json: {error: {msg: "Failed to write record"}}
        return
      end
    end

    # Ceate has_component object
    has_component = create_has_component(publicnote_holding, remark_holding)

    # Create holding object
    holding_record = create_holding_record(electronic_record_id, has_component)

    # Write the holding to Libris XL
    if dry_run
      holding_record_id = "test_holding_id"
    else
      holding_record_id = LibrisxlApi.write_record(token, holding_record)
      if !holding_record_id
        render status: :internal_server_error, json: {error: {msg: "Failed to write holding"}}
        return
      end
    end

    # Return the new id
    render status: :created, json: {electronic_item_id: electronic_record_id, holding_id: holding_record_id}
  end


  def create_electronic_record(reproduction_of, bibliography, issuanceType, has_title, instance_of, associated_media, production)
    # Create electronic record object
    {
      "@graph": [
        {
          "@id": "https://id.kb.se/TEMPID",
          "@type": "Record",
          "mainEntity": {
            "@id": "https://id.kb.se/TEMPID#it"
          },
          "descriptionConventions": [
            {
              "@id": "https://id.kb.se/marc/Isbd"
            },
            {
              "@type": "DescriptionConventions",
              "code": "rda"
            }
          ],
          "marc:catalogingSource": {
            "@id": "https://id.kb.se/marc/CooperativeCatalogingProgram"
          },
          "descriptionLanguage": {
            "@id": "https://id.kb.se/language/swe"
          },
          "encodingLevel": "marc:MinimalLevel",
          "bibliography": bibliography
        },
        {
          "@id": "https://id.kb.se/TEMPID#it",
          "@type": "Electronic",
          "issuanceType": issuanceType,
          "carrierType": [
            {
              "@id": "https://id.kb.se/term/rda/OnlineResource"
            }
          ],
          "production": production,
          "associatedMedia": associated_media,
          "reproductionOf": reproduction_of,
          "hasTitle": has_title,
          "instanceOf": instance_of
        }
      ]
    }
  end

  def create_reproduction_of(id)
    {
      "@id": "#{ENV['LIBRIS_API_BASE_URL']}/#{id}#it"
    }
  end

  def create_bibliography(codes)
    # Loop through the codes and create a bibliography object for each code, then return them in an array
    codes.map do |code|
      {
        "@id": "#{ENV['LIBRIS_API_BASE_URL']}/library/#{code}"#,
      }
    end
  end

  def create_associated_media(url, publicnote, remark)
    # create associated_media array with base object
    associated_media = [
      {
        "@type": "MediaObject",
        "uri": [
          url
        ]
      }
    ]

    # If publicnote is present, add it to the associated_media object
    if publicnote.present?
      associated_media[0]["marc:publicNote"] = [
        publicnote
      ]
    end

    # If remark is present, add it to the associated_media object
    if remark.present?
      associated_media[0]["cataloguersNote"] = [
        remark
      ]
    end

    # Return the associated_media object
    associated_media
  end

  def create_production(place, agent, type)
    # create production object
    [
      {
        "@type": "Reproduction",
        "date": Time.now.year.to_s,
        "place": [
          {
            "@type": "Place",
            "label": [
              place
            ]
          }
        ],
        "agent": [
          {
            "@type": "Agent",
            "label": [
              agent
            ]
          }
        ],
        "typeNote": type
      }
    ]

  end

  def get_instance_data(record)
    # Get the instance data in the record. It can be founde in the graph array inside an object with the attribute @type = Instance, or if that does not exist, try to find @type = Print
    # See https://id.kb.se/vocab/Instance for more possible values
    instance_data = record["@graph"].find { |obj| obj["@type"] == "Instance" } || record["@graph"].find { |obj| obj["@type"] == "Print" }
    if instance_data.nil?
      raise "No instance data found in the record"
    end
    instance_data
  end

  def create_issuance_type(record)
    # Get the issuanceType from the record.
    get_instance_data(record)["issuanceType"]
  end

  def create_has_title(record)
    # Get the hasTitle array from the record.
    get_instance_data(record)["hasTitle"]

  end

  def create_instance_of(record)
    # Get the instanceOf object from the record.
    get_instance_data(record)["instanceOf"]
  end


  def create_has_component(publicnote, remark)
    # Create has_component array with base object
    has_component = [
      {
        "@type": "Item",
        "heldBy": {
          "@id": "#{ENV['LIBRIS_API_BASE_URL']}/library/#{ENV['SIGEL']}"
        }
      }
    ]

    # If publicnote is present, add it to the has_component object
    if publicnote.present?
      has_component[0]["hasNote"] = [
        {
          "@type": "Note",
          "label": [
            publicnote
          ]
        }
      ]
    end

    # If remark is present, add it to the has_component object
    if remark.present?
      has_component[0]["cataloguersNote"] = [
        remark
      ]
    end

    # Return the has_component object
    has_component
  end

  def create_holding_record(id, has_component)
    {
      "@graph": [
        {
          "@type": "Record",
          "@id": "https://id.kb.se/TEMPID",
          "mainEntity": {
            "@id": "https://id.kb.se/TEMPID#it"
          }
        },
        {
          "@id": "https://id.kb.se/TEMPID#it",
          "@type": "Item",
          "heldBy": {
            "@id": "#{ENV['LIBRIS_API_BASE_URL']}/library/#{ENV['SIGEL']}"
          },
          "itemOf": {
            "@id": "#{ENV['LIBRIS_API_BASE_URL']}/#{id}#it"
          },
          "hasComponent": has_component
        }
      ]
    }
  end
end