require "file_utils"
require "uri"

module ACD
  module Discovery
    struct GitHttpsPullResult
      getter ref : String
      getter repo_slug : String
      getter repo_url : String
      getter repo_dir : String
      getter local_path : String
      getter cloned : Bool
      getter pulled : Bool

      def initialize(
        @ref : String,
        @repo_slug : String,
        @repo_url : String,
        @repo_dir : String,
        @local_path : String,
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
        parsed = parse_ref(ref)
        repo_slug = parsed[:repo_slug]
        repo_url = parsed[:repo_url]
        path = parsed[:path]
        repo_dir = File.join(@cache_root, "git+https", repo_slug)
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

        local_path = path.empty? ? repo_dir : File.join(repo_dir, path)
        unless File.exists?(local_path)
          raise "git+https ref #{ref} resolved to missing path: #{local_path}"
        end

        GitHttpsPullResult.new(
          ref: ref,
          repo_slug: repo_slug,
          repo_url: repo_url,
          repo_dir: repo_dir,
          local_path: local_path,
          cloned: cloned,
          pulled: pulled,
        )
      end

      private def parse_ref(ref : String)
        raw = ref.strip
        raw = raw.sub(/^git\+https:\/\//, "")
        raw = raw.sub(/^https:\/\//, "")

        uri_host = nil.as(String?)
        if ref.starts_with?("https://") || ref.starts_with?("git+https://")
          normalized = ref.sub(/^git\+/, "")
          uri = URI.parse(normalized)
          uri_host = uri.host
          raw = "#{uri.host}#{uri.path}" if uri.host
        end

        parts = raw.split("/")
        host = uri_host || parts[0]?
        owner = parts[1]?
        repo = parts[2]?
        raise "invalid git+https ref #{ref}; expected github.com/owner/repo[/path]" unless host && owner && repo

        repo = repo.sub(/\.git$/, "")
        repo_slug = File.join(host, owner, repo)
        repo_url = "https://#{host}/#{owner}/#{repo}.git"
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
        raise "git+https #{action} failed" unless status.success?
      rescue ex : File::NotFoundError
        raise "git executable not found; git+https runtime requires git"
      end
    end
  end
end
