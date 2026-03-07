require "../frontmatter"

module ACD
  module Skills
    struct LoadedSkill
      getter id : String
      getter file_path : String
      getter name : String
      getter description : String
      getter frontmatter : Hash(String, YAML::Any)
      getter content : String

      def initialize(@id : String, @file_path : String, @name : String, @description : String, @frontmatter : Hash(String, YAML::Any), @content : String)
      end
    end

    class Loader
      def load_dir(path : String) : Array(LoadedSkill)
        return [] of LoadedSkill unless Dir.exists?(path)

        Dir.glob(File.join(path, "*.md")).sort.map do |file|
          content = File.read(file)
          parsed = Frontmatter.parse_markdown(content, file)

          name = parsed.data["name"]?.try(&.as_s?)
          description = parsed.data["description"]?.try(&.as_s?)
          raise "#{file}: skill frontmatter requires 'name'" unless name
          raise "#{file}: skill frontmatter requires 'description'" unless description

          LoadedSkill.new(
            id: File.basename(file, ".md"),
            file_path: file,
            name: name,
            description: description,
            frontmatter: parsed.data,
            content: parsed.body,
          )
        end
      end
    end
  end
end
