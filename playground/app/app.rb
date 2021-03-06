class Playground
  use Rack::Session::Cookie, secret: APP_SECRET

  plugin :environments

  configure :development do
    require 'better_errors'

    use BetterErrors::Middleware if defined? BetterErrors
    use Rack::Static, urls: ["/public"]

    BetterErrors::Middleware.allow_ip! "0.0.0.0/0"
    BetterErrors.application_root = Dir.pwd
  end

  plugin :wedge, {
    scope: self,
    plugins: [:form, :ability_list],
    app_dir: RACK_ENV != 'test' ? 'app' : 'playground/app',
    settings: {
      uploader: {
        aws_access_key_id: AWS_ACCESS_KEY_ID,
        aws_secret_access_key: AWS_SECRET_ACCESS_KEY,
        bucket: AWS_BUCKET
      }
    }
  }

  wedge_plugin(:current_user, client_fields: %w'id first_name last_name is_admin') do
    User.find(1)
  end

  # builder = Opal::Builder.new(:stubs=>['opal'])
  # builder.append_paths(APP_ROOT)
  # builder.use_gem('opal-jquery')
  # builder.use_gem('wedge')

  plugin :assets, {
    path: "#{APP_ROOT}/../", css_dir: '', js_dir: '', group_subdirs: false,
    # js_opts: { builder: builder }
    css: {
      default: [
        'public/vendor/normalize-css/normalize.css',
        'public/css/styles.css',
        'bower_components/fine-uploader/_build/fine-uploader.css'
      ],
    },
    js: {
      default: [
        'public/vendor/jquery/jquery.js',
        'bower_components/fine-uploader/_build/s3.jquery.fine-uploader.js'
      ],
    }
  }

  route do |r|
    r.wedge_assets
    r.assets

    r.root do
      wedge(:index).to_js :display
    end

    r.on 'uploader' do
      wedge(:uploader).to_js :display
    end
  end
end
