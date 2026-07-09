require "file_utils"
require "uri"

module ACD
  module Discovery
    struct GitHttpsPullResult
      getter ref : String
      getter transport : String
      getter repo_slug : String
      getter repo_url : String
      getter repo_dir : String
      getter local_path : String
      getter workflow_id : String?
      getter cloned : Bool
      getter pulled : Bool

      def initialize(
        @ref : String,
        @transport : String,
        @repo_slug : String,
        @repo_url : String,
        @repo_dir : String,
        @local_path : String,
        @workflow_id : String?,
        @cloned : Bool,
        @pulled : Bool,
      )
      end
    end

    class GitHttpsPuller
      def initialize(cache_root : String? = nil)
        @cache_root = cache_root || self.class.default_cache_root
      end

      def self.default_cache_root : String
        if explicit = ENV["OCAWE_CACHE_DIR"]?
          return File.expand_path(explicit)
        end

        if xdg = ENV["XDG_CACHE_HOME"]?
          return File.join(File.expand_path(xdg), "ocawe")
        end

        home = ENV["HOME"]? || "."
        File.join(File.expand_path(home), ".cache", "ocawe")
      end

      def pull(ref : String) : GitHttpsPullResult
        pull(ref, "git+https")
      end

      def pull(ref : String, transport : String) : GitHttpsPullResult
        parsed = parse_ref(ref, transport)
        repo_slug = parsed[:repo_slug]
        repo_url = parsed[:repo_url]
        path = parsed[:path]
        repo_dir = File.join(@cache_root, transport, repo_slug)
        cloned = false
        pulled = false

        if Dir.exists?(File.join(repo_dir, ".git"))
          run_git(["-C", repo_dir, "pull", "--ff-only"], "pull #{repo_slug}")
          pulled = true
        else
          FileUtils.mkdir_p(File.dirname(repo_dir))
          run_git(["clone", repo_url, repo_dir], "clone #{repo_slug}")
          cloned = true
        end

        workflow_id = nil.as(String?)
        local_path = path.empty? ? repo_dir : File.join(repo_dir, path)
        unless File.exists?(local_path)
          parent = File.dirname(local_path)
          if File.exists?(parent) && ACD::Discovery::CawfileLoader.find_cawfile(parent)
            workflow_id = File.basename(local_path)
            local_path = parent
          end
        end
        unless File.exists?(local_path)
          raise "#{transport} ref #{ref} resolved to missing path: #{local_path}"
        end

        GitHttpsPullResult.new(
          ref: ref,
          transport: transport,
          repo_slug: repo_slug,
          repo_url: repo_url,
          repo_dir: repo_dir,
          local_path: local_path,
          workflow_id: workflow_id,
          cloned: cloned,
          pulled: pulled,
        )
      end

      private def parse_ref(ref : String, transport : String)
        raw = ref.strip
        raw = raw.sub(/^git\+ssh:\/\//, "ssh://")
        raw = raw.sub(/^git\+https:\/\//, "")
        raw = raw.sub(/^https:\/\//, "")

        uri_host = nil.as(String?)
        ssh_user = "git"
        if raw.starts_with?("ssh://")
          uri = URI.parse(raw)
          uri_host = uri.host
          ssh_user = uri.user || ssh_user
          raw = "#{uri.host}#{uri.path}" if uri.host
        elsif ref.starts_with?("https://") || ref.starts_with?("git+https://")
          normalized = ref.sub(/^git\+/, "")
          uri = URI.parse(normalized)
          uri_host = uri.host
          raw = "#{uri.host}#{uri.path}" if uri.host
        end

        parts = raw.split("/")
        host = uri_host || parts[0]?
        owner = parts[1]?
        repo = parts[2]?
        raise "invalid #{transport} ref #{ref}; expected github.com/owner/repo[/path], git+https://github.com/owner/repo[/path], or git+ssh://github.com/owner/repo[/path]" unless host && owner && repo

        repo = repo.sub(/\.git$/, "")
        repo_slug = File.join(host, owner, repo)
        repo_url = if transport == "git+ssh"
                     "#{ssh_user}@#{host}:#{owner}/#{repo}.git"
                   else
                     "https://#{host}/#{owner}/#{repo}.git"
                   end
        path = parts.size > 3 ? parts[3..].join("/") : ""

        {repo_slug: repo_slug, repo_url: repo_url, path: path}
      end

      private def run_git(args : Array(String), action : String) : Nil
        status = Process.run(
          "git",
          args: args,
          input: Process::Redirect::Close,
          output: Process::Redirect::Inherit,
          error: Process::Redirect::Inherit
        )
        raise "#{action} failed" unless status.success?
      rescue ex : File::NotFoundError
        raise "git executable not found; git transport runtimes require git"
      end
    end
  end
end
