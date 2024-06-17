# typed: true
# frozen_string_literal: true

require "dependabot/shared_helpers"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/file_updaters/vendor_updater"

module Dependabot
  module Helm
    class FileUpdater < Dependabot::FileUpdaters::Base
      require_relative "file_updater/chart_updater"

      def initialize(dependencies:, dependency_files:, repo_contents_path: nil,
                     credentials:, options: {})
        super

        @goprivate = options.fetch(:goprivate, "*")
        use_repo_contents_stub if repo_contents_path.nil?
      end

      def self.updated_files_regex
        [
          /^Chart\.yaml$/,
          /^Chart\.lock$/
        ]
      end

      def updated_dependency_files
        updated_files = []

        if chart_yaml && dependency_changed?(chart_yaml)
          updated_files <<
            updated_file(
              file: chart_yaml,
              content: file_updater.updated_chart_yaml_content
            )

          if chart_lock && chart_lock.content != file_updater.updated_chart_lock_content
            updated_files <<
              updated_file(
                file: chart_lock,
                content: file_updater.updated_chart_lock_content
              )
          end

          vendor_updater.updated_vendor_cache_files(base_directory: directory)
                        .each do |file|
            updated_files << file
          end
        end

        raise "No files changed!" if updated_files.none?

        updated_files
      end

      private

      def dependency_changed?(chart_yaml)
        # file_changed? only checks for changed requirements. Need to check for indirect dep version changes too.
        file_changed?(chart_yaml) || dependencies.any? { |dep| dep.previous_version != dep.version }
      end

      def check_required_files
        return if chart_yaml

        raise "No Chart.yaml!"
      end

      def use_repo_contents_stub
        @repo_contents_stub = true
        @repo_contents_path = Dir.mktmpdir

        Dir.chdir(@repo_contents_path) do
          dependency_files.each do |file|
            path = File.join(@repo_contents_path, directory, file.name)
            path = Pathname.new(path).expand_path
            FileUtils.mkdir_p(path.dirname)
            File.write(path, file.content)
          end

          # Only used to create a backup git config that's reset
          SharedHelpers.with_git_configured(credentials: []) do
            `git config --global user.email "no-reply@github.com"`
            `git config --global user.name "Dependabot"`
            `git config --global init.defaultBranch "placeholder-default-branch"`
            `git init .`
            `git add .`
            `git commit -m'fake repo_contents_path'`
          end
        end
      end

      def chart_yaml
        @chart_yaml ||= get_original_file("Chart.yaml")
      end

      def chart_lock
        @chart_lock ||= get_original_file("Chart.lock")
      end

      def file_updater
        @file_updater ||=
          ChartYamlUpdater.new(
            dependencies: dependencies,
            dependency_files: dependency_files,
            credentials: credentials,
            repo_contents_path: repo_contents_path,
            directory: directory,
            # TODO: FIX THIS
            options: { tidy: tidy?, vendor: vendor?, goprivate: @goprivate }
          )
      end
    end
  end
end

Dependabot::FileUpdaters
  .register("helm", Dependabot::Helm::FileUpdater)
