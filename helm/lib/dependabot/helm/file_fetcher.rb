# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Helm
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig
      extend T::Helpers

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.include?("Chart.yaml")
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a Chart.yaml."
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        # Ensure we always check out the full repo contents for helm chart
        # updates.
        SharedHelpers.in_a_temporary_repo_directory(
          directory,
          clone_repo_contents
        ) do
          fetched_files = chart_yaml ? [chart_yaml] : []
          # Fetch the (optional) Chart.lock
          fetched_files << T.must(chart_lock) if chart_lock
          fetched_files
        end
      end

      private

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def chart_yaml
        @chart_yaml ||= T.let(fetch_file_if_present("Chart.yaml"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def chart_lock
        @chart_lock ||= T.let(fetch_file_if_present("Chart.lock"), T.nilable(Dependabot::DependencyFile))
      end
    end
  end
end

Dependabot::FileFetchers
  .register("helm", Dependabot::Helm::FileFetcher)
