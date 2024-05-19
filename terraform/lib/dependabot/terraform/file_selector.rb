# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/terraform/file_filter"

module Dependabot
  module Terraform
    module FileSelector
      extend T::Sig
      extend T::Helpers

      abstract!

      sig { abstract.returns(T::Array[Dependabot::DependencyFile]) }
      def dependency_files; end

      private

      include FileFilter

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def terraform_files
        dependency_files.select { |f| f.name.end_with?(".tf") }
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def terragrunt_files
        dependency_files.select { |f| terragrunt_file?(f.name) }
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def lockfile
        dependency_files.find { |f| lockfile?(f.name) }
      end
    end
  end
end
