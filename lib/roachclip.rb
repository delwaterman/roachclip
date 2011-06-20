require 'set'
require 'tempfile'
require 'paperclip'
require 'joint'
# require 'roachclip/validations'

module Paperclip
  class << self
    def log *args
    end
  end
end

module Roachclip
  autoload :Version, 'roachclip/version'

  class InvalidAttachment < StandardError; end

  def self.configure(model)
    model.plugin Joint
    model.class_inheritable_accessor :roaches
    model.roaches = Set.new
  end

  module ClassMethods
    def roachclip name, options = {}
      self.attachment name

      raise InvalidAttachment unless attachment_names.include?(name)

      path = options.delete(:path) || "/gridfs/fs/%s-%s"
      self.roaches << {:name => name, :options => options}

      options[:default_style] ||= :original
      
      options[:styles] ||= {}
      options[:styles].each { |k,v| self.attachment "#{name}_#{k}" unless k == options[:default_style] }

      before_save :process_roaches
      before_save :destroy_nil_roaches

      self.send(:define_method, "#{name}_path") do
        time = self.attributes['updated_at'] || Time.now
        time = time.to_i
        (path % [self.send(name).id.to_s, time]).chomp('-')
      end
 
      options[:styles].each do |k,v|
        self.send(:define_method, "#{name}_#{k}_path") do
          time = self.attributes['updated_at'] || Time.now
          time = time.to_i
          (path % [self.send("#{name}_#{k}").id.to_s, time]).chomp('-')
        end
      end
    end

    def validates_roachclip(*args)
      # add_validations(args, Roachclip::Validations::ValidatesPresenceOf)
      add_validations(args, ::ActiveModel::Validations::PresenceValidator)
    end
  end

  module InstanceMethods
    def process_roaches
      roaches.each do |img|
        name = img[:name]
        styles = img[:options][:styles]
        default_style = img[:options][:default_style]
        
        return unless assigned_attachments[name]

        src = Tempfile.new ["roachclip", name.to_s].join('-')
        src.write assigned_attachments[name].read
        src.close
        
        assigned_attachments[name].rewind

        styles.keys.each do |style_key|
          thumbnail = Paperclip::Thumbnail.new src, styles[style_key]
          tmp_file_name = thumbnail.make
          stored_file_name = send("#{name}_name").gsub(/\.(\w*)\Z/) { "_#{style_key}.#{$1}" }

          if style_key == default_style
            send "#{name}=", tmp_file_name
            send "#{name}_name=", stored_file_name
          else
            send "#{name}_#{style_key}=", tmp_file_name
            send "#{name}_#{style_key}_name=", stored_file_name
          end
        end
      end
    end

    def destroy_nil_roaches
      roaches.each do |img|
        name = img[:name]
        styles = img[:options][:styles]
        default_style = img[:options][:default_style]
        
        return unless @nil_attachments && @nil_attachments.include?(name)

        styles.keys.each do |style_key|
          send "#{name}_#{style_key}=", nil unless style_key == default_style
        end
      end
    end
  end
end
