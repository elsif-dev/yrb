# frozen_string_literal: true

require "thor"
require "fileutils"
require "shellwords"

module Commands
  class Worktree < Thor
    PROJECT_ROOT = File.expand_path("../..", __dir__)
    WORKTREES_DIR = File.join(File.dirname(PROJECT_ROOT), "worktrees")

    desc "create NAME", "Create a new git worktree"
    option :branch, aliases: "-b", type: :string, desc: "Git branch to create worktree from (defaults to NAME)"
    def create(name)
      validate_name!(name)

      branch = options[:branch] || name
      worktree_path = File.join(WORKTREES_DIR, name)

      if File.exist?(worktree_path)
        abort("Worktree '#{name}' already exists at #{worktree_path}")
      end

      FileUtils.mkdir_p(WORKTREES_DIR)

      say("Creating worktree '#{name}' from branch '#{branch}'...", :green)
      cmd = "git worktree add #{shell_escape(worktree_path)} -b #{shell_escape(branch)}"
      run_command!(cmd)

      symlink_local_gems

      say("Installing dependencies...", :yellow)
      run_command!("bundle install", chdir: worktree_path)

      say("\nWorktree '#{name}' created!", :green)
      say("  Path:   #{worktree_path}")
      say("  Branch: #{branch}")
      say("\n  cd #{worktree_path}")
    end

    desc "remove NAME", "Remove a git worktree"
    def remove(name)
      worktree_path = File.join(WORKTREES_DIR, name)

      unless File.exist?(worktree_path)
        abort("Worktree '#{name}' not found at #{worktree_path}")
      end

      say("Removing worktree '#{name}'...", :yellow)

      cmd = "git worktree remove #{shell_escape(worktree_path)} --force"
      run_command!(cmd)

      branch = `git branch --list #{shell_escape(name)} 2>/dev/null`.strip
      unless branch.empty?
        system("git", "branch", "-D", name)
        say("  Deleted branch '#{name}'", :green)
      end

      say("Worktree '#{name}' removed!", :green)
    end

    desc "list", "List all git worktrees"
    def list
      unless File.exist?(WORKTREES_DIR)
        say("No worktrees found.", :yellow)
        return
      end

      worktrees = Dir.glob(File.join(WORKTREES_DIR, "*")).select { |path| File.directory?(path) && !File.symlink?(path) }

      if worktrees.empty?
        say("No worktrees found.", :yellow)
        return
      end

      say("Git Worktrees:", :green)
      say("")

      worktrees.sort.each do |path|
        name = File.basename(path)
        branch_output = `git -C #{shell_escape(path)} branch --show-current 2>/dev/null`.strip
        branch = branch_output.empty? ? "unknown" : branch_output

        say("#{name}:", :green)
        say("  Branch: #{branch}")
        say("  Path:   #{path}")
        say("")
      end
    end

    private

    def validate_name!(name)
      pattern = /\A[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\z/
      return if name.match?(pattern)

      abort("Invalid worktree name '#{name}'. " \
            "Must start and end with alphanumeric characters, " \
            "and may contain hyphens in the middle.")
    end

    def symlink_local_gems
      gemfile_path = File.join(PROJECT_ROOT, "Gemfile")
      return unless File.exist?(gemfile_path)

      File.readlines(gemfile_path).each do |line|
        next unless line =~ /path:\s*["']([^"']+)["']/

        relative_path = Regexp.last_match(1)
        source = File.expand_path(relative_path, PROJECT_ROOT)
        target = File.join(WORKTREES_DIR, File.basename(source))

        next if File.exist?(target)
        next unless File.exist?(source)

        FileUtils.ln_s(source, target)
        say("  Symlinked #{File.basename(source)} -> #{source}", :green)
      end
    end

    def shell_escape(str)
      Shellwords.escape(str)
    end

    def run_command!(cmd, chdir: nil)
      opts = chdir ? {chdir: chdir} : {}
      system(cmd, **opts) || abort("Command failed: #{cmd}")
    end
  end
end
