# frozen_string_literal: true

require "English"
require "open3"
require "rainbow"
require "active_support"
require "active_support/core_ext/string"

module ReactOnRails
  module Utils
    TRUNCATION_FILLER = "\n... TRUNCATED ...\n"

    # https://forum.shakacode.com/t/yak-of-the-week-ruby-2-4-pathname-empty-changed-to-look-at-file-size/901
    # return object if truthy, else return nil
    def self.truthy_presence(obj)
      if obj.nil? || obj == false
        nil
      else
        obj
      end
    end

    # Wraps message and makes it colored.
    # Pass in the msg and color as a symbol.
    def self.wrap_message(msg, color = :red)
      wrapper_line = ("=" * 80).to_s
      fenced_msg = <<~MSG
        #{wrapper_line}
        #{msg.strip}
        #{wrapper_line}
      MSG

      Rainbow(fenced_msg).color(color)
    end

    def self.object_to_boolean(value)
      [true, "true", "yes", 1, "1", "t"].include?(value.instance_of?(String) ? value.downcase : value)
    end

    def self.server_rendering_is_enabled?
      ReactOnRails.configuration.server_bundle_js_file.present?
    end

    # Invokes command, exiting with a detailed message if there's a failure.
    def self.invoke_and_exit_if_failed(cmd, failure_message)
      stdout, stderr, status = Open3.capture3(cmd)
      unless status.success?
        stdout_msg = stdout.present? ? "\nstdout:\n#{stdout.strip}\n" : ""
        stderr_msg = stderr.present? ? "\nstderr:\n#{stderr.strip}\n" : ""
        msg = <<~MSG
          React on Rails FATAL ERROR!
          #{failure_message}
          cmd: #{cmd}
          exitstatus: #{status.exitstatus}#{stdout_msg}#{stderr_msg}
        MSG

        puts wrap_message(msg)

        # Rspec catches exit without! in the exit callbacks
        exit!(1)
      end
      [stdout, stderr, status]
    end

    def self.server_bundle_path_is_http?
      server_bundle_js_file_path =~ %r{https?://}
    end

    def self.server_bundle_js_file_path
      # Either:
      # 1. Using same bundle for both server and client, so server bundle will be hashed in manifest
      # 2. Using a different bundle (different Webpack config), so file is not hashed, and
      #    bundle_js_path will throw so the default path is used without a hash.
      # 3. The third option of having the server bundle hashed and a different configuration than
      #    the client bundle is not supported for 2 reasons:
      #    a. The webpack manifest plugin would have a race condition where the same manifest.json
      #       is edited by both the webpack-dev-server
      #    b. There is no good reason to hash the server bundle name.
      return @server_bundle_path if @server_bundle_path && !Rails.env.development?

      bundle_name = ReactOnRails.configuration.server_bundle_js_file
      @server_bundle_path = if ReactOnRails::WebpackerUtils.using_webpacker?
                              begin
                                bundle_js_file_path(bundle_name)
                              rescue Webpacker::Manifest::MissingEntryError
                                File.expand_path(
                                  File.join(ReactOnRails::WebpackerUtils.webpacker_public_output_path,
                                            bundle_name)
                                )
                              end
                            else
                              bundle_js_file_path(bundle_name)
                            end
    end

    def self.bundle_js_file_path(bundle_name)
      if ReactOnRails::WebpackerUtils.using_webpacker? && bundle_name != "manifest.json"
        ReactOnRails::WebpackerUtils.bundle_js_uri_from_webpacker(bundle_name)
      else
        # Default to the non-hashed name in the specified output directory, which, for legacy
        # React on Rails, this is the output directory picked up by the asset pipeline.
        # For Webpacker, this is the public output path defined in the webpacker.yml file.
        File.join(generated_assets_full_path, bundle_name)
      end
    end

    def self.running_on_windows?
      (/cygwin|mswin|mingw|bccwin|wince|emx/ =~ RUBY_PLATFORM) != nil
    end

    def self.rails_version_less_than(version)
      @rails_version_less_than ||= {}

      return @rails_version_less_than[version] if @rails_version_less_than.key?(version)

      @rails_version_less_than[version] = begin
        Gem::Version.new(Rails.version) < Gem::Version.new(version)
      end
    end

    # rubocop:disable Naming/VariableNumber
    def self.rails_version_less_than_4_1_1
      rails_version_less_than("4.1.1")
    end
    # rubocop:enable Naming/VariableNumber

    module Required
      def required(arg_name)
        raise ReactOnRails::Error, "#{arg_name} is required"
      end
    end

    def self.prepend_cd_node_modules_directory(cmd)
      "cd \"#{ReactOnRails.configuration.node_modules_location}\" && #{cmd}"
    end

    def self.source_path
      if ReactOnRails::WebpackerUtils.using_webpacker?
        ReactOnRails::WebpackerUtils.webpacker_source_path
      else
        ReactOnRails.configuration.node_modules_location
      end
    end

    def self.using_webpacker_source_path_is_not_defined_and_custom_node_modules?
      return false unless ReactOnRails::WebpackerUtils.using_webpacker?

      !ReactOnRails::WebpackerUtils.webpacker_source_path_explicit? &&
        ReactOnRails.configuration.node_modules_location.present?
    end

    def self.generated_assets_full_path
      if ReactOnRails::WebpackerUtils.using_webpacker?
        ReactOnRails::WebpackerUtils.webpacker_public_output_path
      else
        File.expand_path(ReactOnRails.configuration.generated_assets_dir)
      end
    end

    def self.gem_available?(name)
      Gem.loaded_specs[name].present?
    rescue Gem::LoadError
      false
    rescue StandardError
      Gem.available?(name).present?
    end

    # Todo -- remove this for v13, as we don't need both boolean and number
    def self.react_on_rails_pro?
      return @react_on_rails_pro if defined?(@react_on_rails_pro)

      @react_on_rails_pro = gem_available?("react_on_rails_pro")
    end

    # Return an empty string if React on Rails Pro is not installed
    def self.react_on_rails_pro_version
      return @react_on_rails_pro_version if defined?(@react_on_rails_pro_version)

      @react_on_rails_pro_version = if react_on_rails_pro?
                                      Gem.loaded_specs["react_on_rails_pro"].version.to_s
                                    else
                                      ""
                                    end
    end

    def self.smart_trim(str, max_length = 1000)
      # From https://stackoverflow.com/a/831583/1009332
      str = str.to_s
      return str unless str.present? && max_length >= 1
      return str if str.length <= max_length

      return str[0, 1] + TRUNCATION_FILLER if max_length == 1

      midpoint = (str.length / 2.0).ceil
      to_remove = str.length - max_length
      lstrip = (to_remove / 2.0).ceil
      rstrip = to_remove - lstrip
      str[0..(midpoint - lstrip - 1)] + TRUNCATION_FILLER + str[(midpoint + rstrip)..-1]
    end

    def self.find_most_recent_mtime(files)
      files.reduce(1.year.ago) do |newest_time, file|
        mt = File.mtime(file)
        mt > newest_time ? mt : newest_time
      end
    end
  end
end
