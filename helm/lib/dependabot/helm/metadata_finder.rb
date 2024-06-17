# typed: true
# frozen_string_literal: true

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/helm/path_converter"

module Dependabot
  module Helm
    class MetadataFinder < Dependabot::MetadataFinders::Base
      private

      def look_up_source
        url = Dependabot::Helm::PathConverter.git_url_for_path(dependency.name)
        Source.from_url(url) if url
      end
    end
  end
end

Dependabot::MetadataFinders
  .register("helm", Dependabot::Helm::MetadataFinder)
