
=begin
assert{ 2.1 } reinvents assert{ 2.0 } for Ruby 1.9.
=end

=begin
assert{ 2.0 } is the industry's most aggressive TDD system

...for Ruby, or any other language. Each time it fails, it analyzes the 
reason and presents a complete report. This makes the cause very
easy to rapidly identify and fix. assert{ 2.0 } is like a debugger's
"inspect variable" system, and it makes your TDD cycle more
effective.

Here's an example of assert{ 2.1 } failing. The first line reflects the 
source of the entire assertion:

     assert{ z =~ /=begon/ } # complete with comments
  --> nil
             z --> "<span style=\"display: none;\">=begin</span>"
 z =~ /=begon/ --> nil.

The second line, --> nil, is the return value of the asserted expression.
The next lines contain the complete source and re-evaluation of each
terminal (z) and expression (z =~ /=begon/) in the assertion's block.

The diagnostic lines are formatted to scan easily, and they use "pretty_inspect"
to wrap complex outputs.

The more creative your assertions, the more elaborate their diagnostics.
These simple techniques free programmers from the tedium of squeezing
assertions into preset patterns, such as assert_equal or assert_match (or
their syntax-sugary equivalents!).

=end

require 'ripper'
require 'test/unit/assertions'
require 'pp'

module Test; module Unit; module Assertions
  
  class AssertionRipper
    MAX_CAPTURE_SNIP = 50  #  TODO  use this when formatting already?
    attr_reader :assertion_source,
                :captures,
                :reflect
    attr_accessor :ripped
    attr_writer :block

    def initialize(called = '')
      if called =~ /([^:]+):(\d+):/
        file, line = $1, $2.to_i
        @ripped = rip(File.readlines(file)[line - 1 .. -1])
      end

      @reflect = ''
      @captures = []
    end

    def rip(lines)
      lines = [lines].flatten
      x = 0

      until exp = Ripper.sexp(@assertion_source = lines[0..x].join)
        (x += 1) >= lines.length and
          raise 'your assertion failed, but your source is ' +
                'incorrectly formatted and resists reflection!' + lines.inspect
      end
      
      return exp.last
    end

    class Nada; end

    attr_accessor :captured_block_vars,
                  :args

    def detect(ident)
      if @args and @captured_block_vars
        ident = "#{@captured_block_vars} = $__args.kind_of?(Array) && $__args.length == 1 ? $__args.first : $__args\n" + 
                ident
        $__args = @args
      end
      return eval(ident, @block.binding)
    rescue ArgumentError => e
      return Nada if e.message =~ /wrong number of arguments \(0 for /
      return e.inspect
    rescue Exception => e
      return e.inspect
    end

    def capture_source
      longness = @reflect.length
      yield
      return @reflect[longness..-1].strip
    end

    def capture(&block)
      snip = capture_source(&block)
      
      if @block
        value = detect(snip)
        capture_snip(snip, value) unless (value == Nada rescue false)
      end
    end

    def capture_snip(snip, value)
      return if snip =~ /^"(.*)"$/ and $1 == value
      return if snip =~ /^\/(.*)\/$/ and $1.match(value)  #  an unmashed string or regexp!
      @captures << [snip, value]
    end

    def extract_block(rippage = @ripped)
      brace_block = rippage.first
      #  CONSIDER  assert brace_block.first == method_add_block
      #        and brace_block.second includes assert
      brace_block = brace_block.last
      if block_var = brace_block[1]
        ripper = AssertionRipper.new
        ripper.sender block_var
        @captured_block_vars = ripper.reflect.sub(/^\|/, '').sub(/\| $/, '')
      end
      return brace_block[2]
    end
    
    #  CONSIDER  extract_block must not skip block-vars - intercept
    #  them here not down there

    def reflect_assertion(block, got)
      self.block = block
      
      extract_block.each do |statement|
        sender statement
      end
      
      inspection = got.pretty_inspect
      
      return format_assertion_result(assertion_source, inspection) + 
               format_captures
    end

    def format_assertion_result(assertion_source, inspection)
      spaces = " --> ".length
      inspection = inspection.split("\n").map{|x| ' ' * spaces + x }.join("\n") 
      return assertion_source.rstrip + "\n --> #{inspection.lstrip}\n"
    end

    def format_capture(width, snip, value)
      return "#{ format_snip(width, snip) } --> #{ format_value(width, value) }"
    end

#  CONSIDER  fix if an assertion contains more than one command - reflect it all!

    def format_snip(width, snip)
      return "%*s" % [width, snip] if snip.length <= width
      chop = snip.scan(/(\w+[[:punct:]]?)/).flatten
      snip = ''
      length = 0
      
      chop.each do |snippet|
        (snip << "\n"; length = 0) if length + snippet.length > width
        snip << snippet
        length += snippet.length
      end
      
      return snip.split("\n").map{|snippet| format_snip(width, snippet) }.join("\n")
    end

    def format_value(width, value)
      width += 4
      source = value.pretty_inspect
      source = source.split("\n").map{|snippet| ' ' * width + snippet }.join("\n")
      return source.lstrip
    end

    def format_captures
      width = @captures.inject(0){|x, (k, v)|  x < k.length ? k.length : x  }
      return @captures.map{|snip, capture| 
                  format_capture width, snip, capture 
                }.join("\n")
    end

    def cycle(args, tween = nil)
      waz = false
      args.each do |arg| 
        if arg and arg != []
          sink tween if tween and waz
          if arg.class == Array and arg.first.class == Array
            cycle arg, tween
          else
            sender arg
          end
          waz = true
        end
      end
    end
    
    def sink(text)
      @reflect << text
    end

    def sender(args)
      send :"_#{args[0]}", *args[1..-1] if args
    end

    def wrap(ldelim, rdelim = ldelim)
      sink ldelim
      yield
      sink rdelim
    end

    %w( tstring_content ).each do |thang|
      define_method '_@' + thang do |arg, at|
        wrap @strung ? '' : '"' do
          arg.gsub!(/(^|[^\\])"/, '\1\"')
          sink arg
        end
      end
    end

    %w( backref const ivar kw ident gvar int 
        op period regexp_end ).each do |thang|
      define_method '_@' + thang do |arg, at|
        sink arg.to_s
      end
    end

    %w( label ).each do |thang|
      define_method '_@' + thang do |arg, at|
        sink ':' + arg.sub(/:$/, '')
      end
    end

    %w( heredoc_end ).each do |thang|
      define_method '_@' + thang do |arg, at|
        raise 'the ripper library cannot see "heredoc" notation. take it out of your block'
      end
    end

    def _command_call(*args)
      sender args.shift
      sink args.shift.to_s
      sender args.shift

      if args.first.compact != [:params]
        sink ' '
      end
      cycle args
    end

    def _super(*args)
      sink 'super'
      cycle args
    end

    def _zsuper(*args)
      sink 'super'
    end

    def _mrhs_add_star(*args)
      sink '*'
      sender args.last[1]
      
      wrap '[', ']' do
        cycle args.last[2..-1]
      end
#      cycle args.last
      #  CONSIDER what's the [] do?
        #~ [[],
         #~ [:aref,
          #~ [:var_ref, [:@ident, "options", [727, 19]]],
          #~ [:args_add_block,
           #~ [[:symbol_literal, [:symbol, [:@ident, "args", [727, 28]]]]],
           #~ false]]]      
    end

    def _command(*args)
      capture do
        args.each do |item|
          if item.first.class == Symbol
            sender item
            sink ' ' if item == args.first
          else
            cycle item
          end
        end
      end
    end
    
    def _bare_assoc_hash(*args);  cycle args, ', ';  end
    
    def _string_literal(*args)
      capture do
        waz_strung = @strung
        @strung = true
        wrap('"'){  cycle args  }
        @strung = waz_strung
      end
    end

    def _string_content(*args)
      cycle args  #  CONSIDER  what be between them?
    end

    def _string_concat(*args)
      cycle args, ' '
    end

    def _dyna_symbol(*args)
      @strung = true
      wrap ':"', '"' do  cycle args  end
      @strung = false
    end

    def _string_embexpr(*args)
      waz_strung = @strung
      @strung = false
      wrap '#{ ', ' }' do  cycle args  end
      @strung = waz_strung
    end

    def _field(*args)
      sender args.shift
      sink args.shift.to_s
      sender args.shift
    end
    
    def _array(*args)
      wrap('[', ']'){  cycle args, ', '  }
    end

    def _regexp_literal(*args)
      capture do
        regexp_end = args.pop
        sender regexp_end
        @strung = true
        cycle args
        @strung = false
        sender regexp_end
      end
    end

    def delimit(what = ', ')
      longness = @reflect.length
      yield
      sink what if longness < @reflect.length
    end

    def _args_add_star(*args)
      delimit do
        cycle args.shift, ', '
      end
      
      sink '*'
      sender args.shift
    end

    def _class(*args)
      sink 'class '
      
      args.compact.each do |arg|
        sink ' < ' if arg == args[1]
        sender arg
      end

      sink "\nend"
    end

    def _void_stmt(*args)
    end

    def _const_ref(*args)
      capture{ sender args.last }
    end

    def _aref_field(*args)
      sender args.shift
      wrap('[', ']'){ sender args.shift }
    end

    def _def(*args)  #  the irony _is_ lost on us...
      sink 'def '
      sender args.shift

      if args.first.first == :paren
        wrap '(', ')' do
          sender args.shift.last
        end
      elsif args.first.compact != [:params]
        sink ' '
      end

      cycle args
      sink "end"
    end
    
    def _defs(*args)
      sink 'def '
      cycle args
      sink "end\n"
    end

    def _for(*args)
      sink 'for '
      sender args.shift
      sink ' in '
      sender args.shift
      sink "\n"
      cycle args
      sink "\nend"
    end

    def _until(*args)
      sink 'until '
      sender args.shift
      sink "\n"
      cycle args
      sink "\nend"
    end

    def _while(*args)
      sink 'while '
      sender args.shift
      sink "\n"
      cycle args
      sink "\nend"
    end

    def _body_stmt(*args)
      wrap "\n" do
        cycle args.shift, "\n"
      end

      cycle args, "\n"
    end

    def _break(*args)
      sink "break\n"
    end

    def _rescue(*args)
      sink "rescue"
      sink ' ' if args[0]

      if args[0] and args[0].first.class == Array
        cycle args[0] 
      else
        sender args[0]
      end

      sink ' => ' if args[1]
      sender args[1] if args[1]
      cycle args[2], "\n" 
    end
    
    def _ensure(*args)
      sink "ensure\n"
      cycle args, "\n"
    end

    def _call(*args)
      capture do
        if args.first.first.class == Array
          wrap('[ ', ' ]'){  cycle args.shift, ', '  }
        else
          sender args.shift
        end

        sink args.shift.to_s
        sender args.shift
      end
    end

    def _const_path_ref(*args)
      capture do
        args.each do |arg|
          sink '::' unless arg == args.first
          sender arg
        end
      end
    end
 
    def _dot2(*args);  cycle args, '..';  end
    def _dot3(*args);  cycle args, '...';  end

    def _aref(*args)
      capture do
        sender args.shift
        wrap('[', ']'){  sender args.shift  }
      end
    end

    def _if(*args)
      sink "if "
      sender args.shift
      sink "\n"
      cycle args
      sink "\nend"
    end

    def _unless(*args)
      sink "unless "
      sender args.shift
      sink "\n"
      cycle args
      sink "\nend"
    end

    def _assoclist_from_args(*args)
      cycle args, ', '
    end

    def _hash(*args)
      wrap('{ ', ' }'){  cycle args, ', '  }
    end

    def _else(*args)
      sink "\nelse\n"
      cycle args
    end

    def _elsif(*args)
      sink "\nelsif "
      sender args.shift
      sink "\n"
      cycle args
    end

    def _fcall(*args);  sender *args;  end
    def _method_add_arg(*args); capture{  cycle args  };  end
    def _method_add_block(*args);  capture{  cycle args  };  end
    def _var_field(*args);  cycle args, ', ';  end
    
    def _binary(from, op, to)
      capture do
        sender from
        sink " #{op} "
        sender to
      end
    end

    def _brace_block(*args)
      sink '{ '
      sender args.shift
      cycle args.first, "\n"
      sink ' }'
    end
    
    def _do_block(*args)
      sink " do\n"
      sender args.shift
      cycle args.first, "\n"
      sink "\nend"
    end

    def _assign(*args)
      sender args.shift
      sink ' = '

      if args.first.first.class == Array
        wrap('[ ', ' ]'){  cycle args, ', '  }
      else
        cycle args, ', '
      end
    end
    
    def _arg_paren(*args);
      sink '('
      cycle args, ', '
      sink ')'
    end
    
    def _symbol_literal(*args)
      cycle args, ', '
    end
    
    def _symbol(*args);  
      sink ':'
      cycle args, ', '
    end

    def _yield0;  sink 'yield';  end
    def _opassign(*args);  cycle args, ' ';  end
    
    def _rest_param(*args)
      sink '*'
      cycle args
    end
    
    def _block_var(*args)
      params = args.first[1]
      rest_param = args.first[3]
      blockarg = args.first[5]
      sink '|'
      
      cycle params, ', ' if params
      
      if rest_param
        sink ', ' if params
        sender rest_param 
      end
      
      if blockarg
        sink ', ' if params or rest_param
        sender blockarg 
      end

      sink '| '
    end  #  CONSIDER  just call cycle already!

    def _params(*args)
      cycle args, ', '
    end

    def _yield(*args)
      if args.first.first == :paren
        sink 'yield('
        sender args.first.last
        sink ')'
      end
    end

    def _paren(*args)
      sink '('
      cycle args.last, "\n"
      sink ')'
    end   

    def _blockarg(*args)
      sink '&'
      sender args.first
    end

    def _begin(*args)
      sink "begin"
      sender args.shift
      sink "\nend"
    end

    def _mlhs_paren(*args)
      if args.first.first.class == Array
        sink '('
        cycle args.first, ', '
        sink ')'
      else
        sender args.first
      end
    end

    def _assoc_new(*args)
      cycle args, ' => '
    end

    def _unary(*args)
      capture do
        sink arg = args.shift.to_s
        sink ' ' if arg == 'not'
        cycle args
      end
    end

    def _var_ref(args);  capture{  sender args  };  end
    def _class_name_error(args);  capture{  sender args  };  end
    
    def _args_add_block(*args)
      baseline = @reflect.length
      if args.first.first.class == Array
        cycle args.shift, ', '
      else 
        thing = args.shift 
        sender thing if thing.any?
      end
      if args.first
        sink ', ' if @reflect.length > baseline
        sink '&'
        sender args.first 
      end
    end
    
    def _massign(*args)
      cycle args.shift, ', '
      sink ' = '
      cycle args
    end
    
    def _module(*args)
      sink 'module '
      sender args.shift
      sender args.shift
      sink 'end'
    end
    
    def _mrhs_new_from_args(*args)  cycle args, ', '  end
    
    def _if_mod(*args)
      sender args.last
      sink ' if '
      sender args.first
    end
    
    def _unless_mod(*args)
      sender args.last
      sink ' unless '
      sender args.first
    end
    
    def _ifop(*args)
      sender args.shift
      sink ' ? '
      sender args.shift
      sink ' : '
      sender args.shift
    end
    
    def _return0(*args)
      sink 'return'
    end
    
    def _return(*args)
      sink 'return '
      cycle args, ', '
    end
    
    def _alias(*args)
      cycle args, ' '
    end
    
    def _method_missing(*args)
      puts "    rippage = #{ args.pretty_inspect } "
    end

  end
  
  #!doc!
  def assert(*args, &block)
  #  This assertion calls a block, and faults if it returns
  #  +false+ or +nil+. The fault diagnostic will reflect the
  #  assertion's complete source - with comments - and will
  #  reevaluate the every variable and expression in the
  #  block.
  #
  #  The first argument can be a diagnostic string:
  #
  #    assert("foo failed"){ foo() }
  #
  #  The fault diagnostic will print that line.
  # 
  #  The next time you think to write any of these assertions...
  #  
  #  - +assert+
  #  - +assert_equal+
  #  - +assert_instance_of+
  #  - +assert_kind_of+
  #  - +assert_operator+
  #  - +assert_match+
  #  - +assert_not_nil+
  #  
  #  use <code>assert{ 2.1 }</code> instead.
  #
  #  If no block is provided, the assertion calls +assert_classic+,
  #  which simulates RubyUnit's standard <code>assert()</code>.
  #  
  #  Note: This only works for Ruby 1.9, because it uses the Ripper library,
  #  maintained by Ruby's core team.
  #
    if block
      assert_ *args, &block
    else
      assert_classic *args
    end
    return true # or die trying ;-)
  end

  # This is a copy of the classic assert, so your pre-existing
  # +assert+ calls will not change their behavior
  #
  def assert_classic(boolean, message=nil)
    _wrap_assertion do
      assert_block("assert<classic> should not be called with a block.") { !block_given? }
      assert_block(build_message(message, "<?> is not true.", boolean)) { boolean }
    end
  end

  def reflect(diagnostic = nil, got = nil, called = caller[0],
                options = {},
                &block)
    options = { :args => [], :diagnose => lambda{''} }.merge(options)
    effect = AssertionRipper.new(called)
    effect.args = *options[:args]
     #  only capture the block_vars if there be args?
    add_diagnostic diagnostic
    report = @__additional_diagnostics.uniq + [effect.reflect_assertion(block, got)]
    more_diagnostics = options.fetch(:diagnose, lambda{''}).call.to_s
    report << more_diagnostics if more_diagnostics.length > 0
    return report.compact.join("\n")
  end

  def add_diagnostic(whatever)
    @__additional_diagnostics ||= []
    
    if whatever == :clear
      @__additional_diagnostics = []
    else
      @__additional_diagnostics << whatever if whatever
    end
  end

  def assert_(diagnostic = nil, options = {}, &block)
    return if got = block.call(*options[:args])
    flunk reflect(diagnostic, got, caller[1], options, &block)
  ensure
    @__additional_diagnostics = []
  end

  def deny(diagnostic = nil, options = {}, &block)
    return unless got = block.call(*options[:args])
    flunk reflect(diagnostic, got, caller[0], options, &block)
  ensure
    @__additional_diagnostics = []
  end
  
  alias denigh deny  #  to line assert{ ... } and 
                     #          denigh{ ... } statements up neatly!

end; end; end

require '../test/assert2_test.rb' if $0 == __FILE__ and File.exist?('../test/assert2_test.rb')
#require 'ripdoc_test.rb' if $0 == __FILE__ and File.exist?('ripdoc_test.rb')

class File
  def self.write(filename, contents)
    open(filename, 'w'){|f|  f.write(contents)  }
  end
end