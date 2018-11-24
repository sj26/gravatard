require "active_support/all"
require "digest/md5"
require "image_science"
require "sinatra/base"

class Gravatard::Application < Sinatra::Base
  set :root, File.expand_path("../../../", __FILE__)

  AVATAR_PATH = File.join(settings.root, "avatars")
  AVATAR_DEFAULT = File.join(AVATAR_PATH, "default.png")
  AVATAR_ORIGINAL_PATH = File.join(AVATAR_PATH, "original")

  helpers do
    def recent limit=10
      seen = []
      File.new(File.join(AVATAR_PATH, 'recent.log'), 'r').each do |email_md5|
        email_md5.strip!
        unless seen.include? email_md5
          yield email_md5
          seen << email_md5
          limit -= 1
          break if limit < 1
        end
      end
    rescue Errno::ENOENT
    end
  end

  get '/' do
    haml :home
  end

  post '/upload' do
    email = params[:email].strip.downcase
    halt 401 unless email.present? && email =~ /\A\S+@\S+\.\S{2,}\Z/

    # What are we naming this image?
    email_md5 = Digest::MD5.hexdigest(email).downcase
    avatar_filename = File.join(AVATAR_ORIGINAL_PATH, email_md5)

    # Load up the image
    ImageScience.with_image(params[:avatar][:tempfile].path) do |image|
      # Save the original for later resizing
      image.save avatar_filename

      # Create a 512x512 thumbnail
      format = :jpeg
      size = 512
      Dir.mkdir(File.join(AVATAR_PATH, size.to_s)) unless File.exists? File.join(AVATAR_PATH, size.to_s)
      avatar_thumbnail_filename = File.join(AVATAR_PATH, size.to_s, "#{email_md5}.#{format}")
      image.thumbnail(size) do |thumb|
        thumb.save avatar_thumbnail_filename
      end
    end

    # Keep track of recent avatars
    recent = File.new(File.join(AVATAR_PATH, 'recent.log'), 'a')
    recent.sync = true
    recent << "#{email_md5}\n"

    redirect '/'
  end

  get %r{/avatar/([a-zA-Z0-9\-_]{32})(?:.(png|jpg|jpeg|gif))?} do |email_md5, format|
    email_md5.downcase!
    format = (format || "png").downcase.to_sym
    format = :jpeg if format == :jpg
    size = (params[:s] || params[:size] || 80).to_i

    halt 401, {}, ["Size invalid"] unless 1 <= size && size <= 512

    avatar_filename = File.join(AVATAR_ORIGINAL_PATH, email_md5)
    unless File.exists? avatar_filename
      email_md5 = 'default'
      avatar_filename = AVATAR_DEFAULT
    end

    avatar_thumbnail_filename = File.join(AVATAR_PATH, size.to_s, "#{email_md5}.#{format}")
    if !File.exists?(avatar_thumbnail_filename) || File.stat(avatar_thumbnail_filename).mtime <= File.stat(avatar_filename).mtime
      ImageScience.with_image(avatar_filename) do |image|
        image.thumbnail(size) do |thumb|
          Dir.mkdir File.join(AVATAR_PATH, size.to_s) unless File.exists? File.join(AVATAR_PATH, size.to_s)
          thumb.save avatar_thumbnail_filename
        end
      end
    end

    send_file avatar_thumbnail_filename, :disposition => "inline"
  end

  get %r{/avatar/(\S+?@\S+?\.\S{2,}?)(\.(?:png|jpg|jpeg|gif))?} do |email, format_suffix|
    email = email.strip.downcase
    email_md5 = Digest::MD5.hexdigest(email).downcase

    redirect "/avatar/#{email_md5}#{format_suffix}"
  end

  get "/gravatar.php" do
    query = request.GET.dup
    email_md5 = query.delete('gravatar_id').downcase
    halt 400, {}, ['Invalid gravatar ID'] unless email_md5.present? && email_md5 =~ /\A[a-f0-9]{32}\Z/

    redirect "/avatar/#{email_md5}?#{Rack::Utils.build_query(query)}"
  end
end
