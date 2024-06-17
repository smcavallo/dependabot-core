# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "open3"
require "dependabot/dependency"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/helm/path_converter"
require "dependabot/helm/replace_stubber"
require "dependabot/errors"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/helm/version"

module Dependabot
  module Helm
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = Dependabot::FileParsers::Base::DependencySet.new

        dependencies.each do |d|
          reqs = [{
            file: chart_yaml.name,
            groups: [],
            requirement: d["version"],
            source: d["repository"]
          }]

          dependency = Dependency.new(
            name: d["name"],
            package_manager: "helm",
            requirements: reqs,
            version: d["version"]
          )
          dependency_set << dependency if dependency
        end

        dependency_set.dependencies
      end

      private

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def chart_yaml
        @chart_yaml ||= T.let(get_original_file("Chart.yaml"), T.nilable(Dependabot::DependencyFile))
      end

      sig { override.void }
      def check_required_files
        raise "No Chart.yaml!" unless chart_yaml
      end

      sig { params(details: T::Hash[String, T.untyped]).returns(Dependabot::Dependency) }
      def dependency_from_details(details)
        source = { type: "default", source: details["Path"] }
        version = details["Version"]&.sub(/^v?/, "")

        reqs = [{
          requirement: details["Version"],
          file: chart_yaml&.name,
          source: source,
          groups: []
        }]

        Dependency.new(
          name: details["Path"],
          version: version,
          requirements: details["Indirect"] ? [] : reqs,
          package_manager: "helm"
        )
      end

      sig { returns(T::Array[T::Hash[String, T.untyped]]) }
      def required_packages
        @required_packages ||=
          T.let(SharedHelpers.in_a_temporary_directory do |path|
            # Create a fake empty module for each local module so that
            # `go mod edit` works, even if some modules have been `replace`d with
            # a local module that we don't have access to.
            local_replacements.each do |_, stub_path|
              FileUtils.mkdir_p(stub_path)
              FileUtils.touch(File.join(stub_path, "Chart.yaml"))
            end

            File.write("Chart.yaml", chart_yaml_content)

            command = "go mod edit -json"

            stdout, stderr, status = Open3.capture3(command)
            handle_parser_error(path, stderr) unless status.success?
            JSON.parse(stdout)["Require"] || []
          end, T.nilable(T::Array[T::Hash[String, T.untyped]]))
      end

      sig { returns(T::Hash[String, String]) }
      def local_replacements
        @local_replacements ||=
          # Find all the local replacements, and return them with a stub path
          # we can use in their place. Using generated paths is safer as it
          # means we don't need to worry about references to parent
          # directories, etc.
          T.let(ReplaceStubber.new(repo_contents_path).stub_paths(manifest, chart_yamld&.directory),
                T.nilable(T::Hash[String, String]))
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def manifest
        @manifest ||=
          T.let(SharedHelpers.in_a_temporary_directory do |path|
                  File.write("Chart.yaml", chart_yaml&.content)

                  # Parse the go.mod to get a JSON representation of the replace
                  # directives
                  command = "go mod edit -json"

                  stdout, stderr, status = Open3.capture3(command)
                  handle_parser_error(path, stderr) unless status.success?

                  JSON.parse(stdout)
                end, T.nilable(T::Hash[String, T.untyped]))
      end

      sig { returns(T.nilable(String)) }
      def go_mod_content
        local_replacements.reduce(go_mod&.content) do |body, (path, stub_path)|
          body&.sub(path, stub_path)
        end
      end

      sig { params(path: T.any(Pathname, String), stderr: String).returns(T.noreturn) }
      def handle_parser_error(path, stderr)
        msg = stderr.gsub(path.to_s, "").strip
        raise Dependabot::DependencyFileNotParseable.new(T.must(chart_yaml).path, msg)
      end

      sig { params(dep: T::Hash[String, T.untyped]).returns(T::Boolean) }
      def skip_dependency?(dep)
        # Updating replaced dependencies is not supported
        return true if dependency_is_replaced(dep)

        path_uri = URI.parse("https://#{dep['Path']}")
        !path_uri.host&.include?(".")
      rescue URI::InvalidURIError
        false
      end

      sig { params(details: T::Hash[String, T.untyped]).returns(T::Boolean) }
      def dependency_is_replaced(details)
        # Mark dependency as replaced if the requested dependency has a
        # "replace" directive and that either has the same version, or no
        # version mentioned. This mimics the behaviour of go get -u, and
        # prevents that we change dependency versions without any impact since
        # the actual version that is being imported is defined by the replace
        # directive.
        if manifest["Replace"]
          dep_replace = manifest["Replace"].find do |replace|
            replace["Old"]["Path"] == details["Path"] &&
              (!replace["Old"]["Version"] || replace["Old"]["Version"] == details["Version"])
          end

          return true if dep_replace
        end
        false
      end
    end
  end
end

Dependabot::FileParsers
  .register("helm", Dependabot::Helm::FileParser)
