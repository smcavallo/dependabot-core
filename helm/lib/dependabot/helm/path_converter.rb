# typed: true
# frozen_string_literal: true

require "dependabot/helm/native_helpers"

module Dependabot
  module Helm
    module PathConverter
      def self.git_url_for_path(path)
        # TODO: FIX THIS
        # Save a query by manually converting golang.org/x names
        import_path = path.gsub(%r{^golang\.org/x}, "github.com/golang")

        SharedHelpers.run_helper_subprocess(
          command: NativeHelpers.helper_path,
          function: "getVcsRemoteForImport",
          args: { import: import_path }
        )
      end
    end
  end
end
