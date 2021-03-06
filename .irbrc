# Save history
IRB.conf[:SAVE_HISTORY] = 1000

# Copying from IRB
# ----------------

# Copy string into paste buffer (OS Specific)
if RbConfig::CONFIG['host_os'] =~ /darwin/
  def copy string_to_copy
    __with_tmp_file__(string_to_copy) do |tmp_path|
      `cat #{tmp_path} | pbcopy`
    end
  end
elsif File::ALT_SEPARATOR # Windows
  def copy string_to_copy
    __with_tmp_file__(string_to_copy) do |tmp_path|
      `type #{tmp_path} | clip`
    end
  end
end

# Copy to TMUX buffer (must be in a TMUX session... obviously)
if ENV["TMUX"]
  def copy_to_tmux string_to_copy
    __with_tmp_file__(string_to_copy) do |tmp_path|
      `cat #{tmp_path} | tmux load-buffer -`
    end
  end
end


# Edit cmd in editor
# ------------------
#
# Portions of this are borrowed from the `interactive_editor` gem (thanks!).
# License below:
#
# The MIT License
#
# Copyright (c) 2010-2011 Jan Berkel
# Portions Copyright (c) 2006-2007 Giles Bowkett et al.
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# 'Software'), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Four states
#   - Nothing passed, 1st time:  Loads the most recent evaluated code
#   - Nothing passed, Nth time:  Loads most recent tmp file used
#   - :last passed as the file:  Loads the most recent evaluated code
#   - file name passed in:       Loads the file, creating it if it doesn't
def edit file=nil
  raise "Must set $EDITOR to use `edit` method!" unless ENV["EDITOR"]
  raise "Readline not in use!" unless defined?(Readline)

  require 'shellwords'

  @__tmp_edit_files__ ||= []

  edit_data = nil
  file_name = file
  file_name = @__tmp_edit_files__.last if file.nil? && @__tmp_edit_files__.last

  if file_name == :last || file_name.nil?
    edit_data = IRB.CurrentContext.code_chunks[-2].to_s
  end

  if edit_data
    result = nil
    __with_tmp_file__(edit_data, false) do |file_path|
      @__tmp_edit_files__ << file_path

      result = __edit_and_execute file_path
    end
    result
  else
    __edit_and_execute file_name
  end
end

def __edit_and_execute file_path
  cmd  = Shellwords.shellwords(ENV["EDITOR"])
  cmd << file_path

  Kernel.system(*cmd)

  IRB.CurrentContext.replace_last_code_chunk File.read(file_path)
end

IRB.conf[:AT_EXIT] << proc do
                        if defined?(@__edit_files) && @__tmp_edit_files__.is_a?(Array)
                          File.unlink *@__tmp_edit_files__
                        end
                      end


# Helper Methods
# --------------


# Monkey-patch IRB::Context to save fully evaluated code chunks (used for edit)
module IRB
  class Context
    attr_reader :code_chunks

    prepend Module.new {
      def evaluate line, lineno
        save_code_chunk line, lineno
        super
      end
    }

    def save_code_chunk line, lineno
      @code_chunks ||= []
      @code_chunks << [lineno, line]
      @code_chunks.shift if @code_chunks.size > 50
    end

    def replace_last_code_chunk(new_chunk)
      @code_chunks.last[1] = new_chunk
      @workspace.evaluate self, new_chunk, irb_path, @code_chunks.last[0]
    end
  end
end

# Helper method for copying/editing
def __with_tmp_file__ tmpfile_data, unlink = true
  require 'tempfile'

  # When copying, the filename doesn't really matter, but just use `.rb` for
  # the extension everywhere.
  tmpfile = Tempfile.new(['irb_data_buffer', '.rb'])
  begin
    tmpfile.write tmpfile_data
    tmpfile.close

    yield tmpfile.path
  ensure
    tmpfile.unlink if unlink
  end
end
