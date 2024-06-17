# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/nuget/native_helpers"
require "dependabot/shared_helpers"

RSpec.describe Dependabot::Nuget::NativeHelpers do
  let(:dependabot_home) { ENV.fetch("DEPENDABOT_HOME", nil) || Dir.home }

  describe "nuget updater command path" do
    subject(:command) do
      (command,) = described_class.get_nuget_updater_tool_command(repo_root: repo_root,
                                                                  proj_path: proj_path,
                                                                  dependency: dependency,
                                                                  is_transitive: is_transitive)
      command = command.gsub(/^.*NuGetUpdater.Cli/, "/path/to/NuGetUpdater.Cli") # normalize path for unit test
      command
    end

    let(:repo_root) { "/path/to/repo" }
    let(:proj_path) { "/path/to/repo/src/some project/some_project.csproj" }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "Some.Package",
        version: "1.2.3",
        previous_version: "1.2.2",
        requirements: [{ file: "some_project.csproj", requirement: "1.2.3", groups: [], source: nil }],
        previous_requirements: [{ file: "some_project.csproj", requirement: "1.2.2", groups: [], source: nil }],
        package_manager: "nuget"
      )
    end
    let(:is_transitive) { false }

    it "returns a properly formatted command with spaces on the path" do
      expect(command).to eq("/path/to/NuGetUpdater.Cli update --repo-root /path/to/repo " \
                            '--solution-or-project /path/to/repo/src/some\ project/some_project.csproj ' \
                            "--dependency Some.Package --new-version 1.2.3 --previous-version 1.2.2 " \
                            "--verbose")
    end

    context "when invoking tool with spaces in path, it generates expected warning" do
      before do
        allow(Dependabot.logger).to receive(:error)
      end

      it "the tool runs with command line arguments properly interpreted" do
        # This test will fail if the command line arguments weren't properly interpreted
        described_class.run_nuget_updater_tool(repo_root: repo_root,
                                               proj_path: proj_path,
                                               dependency: dependency,
                                               is_transitive: is_transitive,
                                               credentials: [])
        expect(Dependabot.logger).not_to have_received(:error)
      end
    end
  end

  describe "#native_csharp_tests" do
    subject(:dotnet_test) do
      Dependabot::SharedHelpers.run_shell_command(command)
    end

    let(:command) do
      [
        "dotnet",
        "test",
        "--configuration",
        "Release",
        project_path
      ].join(" ")
    end

    context "when the output is from `dotnet test NuGetUpdater.Core.Test` output" do
      let(:project_path) do
        File.join(dependabot_home, "nuget", "helpers", "lib", "NuGetUpdater",
                  "NuGetUpdater.Core.Test", "NuGetUpdater.Core.Test.csproj")
      end

      it "contains the expected output" do
        expect(dotnet_test).to include("Passed!")
      end
    end

    context "when the output is from `dotnet test NuGetUpdater.Cli.Test`" do
      let(:project_path) do
        File.join(dependabot_home, "nuget", "helpers", "lib", "NuGetUpdater",
                  "NuGetUpdater.Cli.Test", "NuGetUpdater.Cli.Test.csproj")
      end

      it "contains the expected output" do
        expect(dotnet_test).to include("Passed!")
      end
    end
  end

  describe "#native_csharp_format" do
    subject(:dotnet_test) do
      Dependabot::SharedHelpers.run_shell_command(command)
    end

    let(:command) do
      [
        "dotnet",
        "format",
        lib_path,
        "--exclude",
        except_path,
        "--verify-no-changes",
        "-v",
        "diag"
      ].join(" ")
    end

    context "when output is from `dotnet format NuGetUpdater` output" do
      let(:lib_path) do
        File.absolute_path(File.join("helpers", "lib", "NuGetUpdater"))
      end

      let(:except_path) { "helpers/lib/NuGet.Client" }

      it "contains the expected output" do
        expect(dotnet_test).to include("Format complete")
      end
    end
  end
end
