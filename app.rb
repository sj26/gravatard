require 'bundler'
Bundler.setup

require 'active_support/all'
require 'digest/md5'
require 'sinatra/base'
require 'rmagick'

module Gravatard
  class Application < Sinatra::Base
    AVATAR_PATH = File.expand_path(File.join(File.dirname(__FILE__), 'avatars'))
    AVATAR_ORIGINAL_PATH = File.join(AVATAR_PATH, 'original')
    
    get '/' do
      haml :home
    end
    
    post '/upload' do
      email = params[:email].strip.downcase
      halt 401 unless email.present? && email =~ /\A\S+@\S+\.\S{2,}\Z/
      
      # What are we naming this image?
      email_md5 = Digest::MD5.hexdigest(email).downcase
      
      # Load up the image
      avatar = Magick::Image::read(params[:avatar][:tempfile].path).first
      halt 401 unless avatar.filesize <= 1024*1024
      avatar.resize_to_fit! 512
      
      # Save the original for later resizing
      avatar_filename = File.join(AVATAR_ORIGINAL_PATH, email_md5)
      avatar.write avatar_filename

      # Save the original as a thumbnail of it's size and format
      size = [avatar.columns, avatar.rows].max
      Dir.mkdir(File.join(AVATAR_PATH, size.to_s)) unless File.exists? File.join(AVATAR_PATH, size.to_s)
      avatar_thumbnail_filename = File.join(AVATAR_PATH, size.to_s, "#{email_md5}.#{avatar.format.downcase}")
      avatar.write avatar_thumbnail_filename
      
      redirect '/'
    end
    
    get %r{\A/avatar/([a-zA-Z0-9\-_]{32})(?:.(png|jpg|jpeg|gif))?\Z} do |email_md5, format|
      email_md5.downcase!
      format = (format || "png").downcase.to_sym
      size = (params[:s] || params[:size] || 80).to_i
      
      halt 401, {}, ["Size invalid"] unless 1 <= size && size <= 512
      
      avatar_filename = File.join(AVATAR_ORIGINAL_PATH, email_md5)
      halt 404, {}, ["Gravatar not found"] unless File.exists? avatar_filename
      
      avatar_thumbnail_filename = File.join(AVATAR_PATH, size.to_s, "#{email_md5}.#{format}")
      if !File.exists?(avatar_thumbnail_filename) || File.stat(avatar_thumbnail_filename).mtime <= File.stat(avatar_filename).mtime
        avatar = Magick::Image::read(avatar_filename).first
        avatar_thumbnail = avatar.resize_to_fit size
        Dir.mkdir File.join(AVATAR_PATH, size.to_s) unless File.exists? File.join(AVATAR_PATH, size.to_s)
        avatar_thumbnail.write avatar_thumbnail_filename
      end
      
      send_file avatar_thumbnail_filename, :disposition => "inline"
    end
    
    get %r{\A/avatar/(\S+?@\S+?\.\S{2,}?)(\.(?:png|jpg|jpeg|gif))?\Z} do |email, format_suffix|
      email = email.strip.downcase
      email_md5 = Digest::MD5.hexdigest(email).downcase
      
      redirect "/avatar/#{email_md5}#{format_suffix}"
    end
  end
end
