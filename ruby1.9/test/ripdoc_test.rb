require 'test/unit'
$:.unshift 'lib'; $:.unshift '../lib'
require 'assert2'
require 'ripdoc'
require 'assert_xhtml'

HomePath = RipDoc::HomePath

#  TODO  assert{} should catch and decorate errors
#  TODO  deny{ xpath } decorates?
#  TODO  make the add_diagnostic take a lambda
#  TODO  censor TODOs from the pretty rip!
#  TODO  give the accordion div the finger emphasis?
#  TODO  move styles like .accordion_toggle to a CSS file
#  TODO  tidy gives a billion warnings. Fix.
#  TODO  change all JPGs to transparently cool PNGs
#  TODO  at scroll time keep the target panel in the viewport!
#  TODO  help stickmanlabs get a macbook pro (or help talk him out of it;)
#  TODO  think of a use for the horizontal accordion, and for nesting them
#  TODO  better style for the page-footer

class RipDocSuite < Test::Unit::TestCase

  def setup
    @rip = RipDoc.new('')
    @output = ''
    @f = StringIO.new(@output)
  end

  def _test_generate_accordion_with_test_file
    assert_xhtml RipDoc.generate(HomePath + 'test/assert2_test.rb', 'assert{ 2.1 }')
    assert{ xpath('/html/head/title').text == 'assert{ 2.1 }' }
    assert{ xpath(:span, style: 'display: none;').text.index('=begin') }
   
    assert do
      xpath :div, :vertical_container do
        xpath(:'h1[ @class = "accordion_toggle accordion_toggle_active" ]').text =~ 
                  /reinvents assert/
      end
    end

    # reveal
  end  #  TODO  why we crash when any other tests generate a ripped doc?

#  TODO  pay for Staff Benda Bilili  ALBUM: Tr�s Tr�s Fort (Promo Sampler) !

  def _test_a_ripped_doc_contains_no_empty_pre_tags
    assert_xhtml RipDoc.generate(HomePath + 'test/assert2_test.rb', 'assert{ 2.1 }')
    
#    xpath :div, :content do
#      deny{ xpath(:'pre').text == "\n" }
  #  end
  end  #  TODO how to constrain the context and then deny inside it?
  
  #  TODO  what are &#13; doing in there?
  #  TODO  snarf all #! commentry
  
  def test_embdocs_form_accordions_with_contents
    assert_xhtml RipDoc.generate(HomePath + 'test/assert2_test.rb', 'assert{ 2.1 }')
    reveal
    assert do
      xpath :div, :vertical_container do
        xpath(:'h1/following-sibling::div[ @class = "accordion_content" ]') # .text =~ 
    #              /complete report/
      end
    end
    deny{ @sauce.match('<p><p>') }
    deny{ @sauce.match('<pre></div>') }
    # reveal
  end

    #  TODO  are # markers leaking into the formatted outputs?

  def test_embdoc_two_indented_lines_have_no_p_between_them
    assert_embdoc ['yo', ' first indented', ' also indented', 'dude']
    denigh{ xpath(:'p[ contains(., "indented") ]') }
    assert{ xpath(:'pre[ contains(., "first indented") and contains(., "also indented") ]') }
    denigh{ xpath(:'p[ . = " " ]') }
  end

  def test_on_embdoc_beg
    assert{ @rip.embdocs.nil? }
    @rip.on_embdoc_beg('=begin', @f)
   # TODO assert{ @output =~ /^\<\/pre>/ }
    assert{ @rip.embdocs == [] }
  end

  def test_on_embdoc
    @rip.embdocs = []
    @rip.on_embdoc('yo', @f)
    denigh{ @output =~ /yo/ }
    assert{ @rip.embdocs == ['yo'] }
    denigh{ @rip.in_nodoc }
  end  #  TODO  a #!nodoc! will skip an =end tag

  def test_nodoc_inside_embdoc
    @rip.embdocs = []
    @rip.on_embdoc('yo', @f)
    @rip.on_embdoc('#!nodoc!', @f)  # TODO  also turn on doc from inside an embdoc!!
    @rip.on_embdoc('dude', @f)
    assert{ @rip.embdocs == ['yo'] }
    assert{ @rip.in_nodoc }
  end  #  TODO  a #!nodoc! will skip an =end tag

  def test_end_panel_after_embdoc_inserts_end_of_div_tag
    @rip.embdocs = []
    @rip.on_comment('#!end_panel!', @f)
    assert{ @output.match('</div>') }
  end

  def test_comments_dont_always_turn_nodoc_off
    @rip.embdocs = []
    @rip.in_nodoc = true
    @rip.on_comment('# non-commanding comment', @f)
    assert{ @rip.in_nodoc }
  end

  def assert_embdoc(array)
    @rip.embdocs = array
    @rip.on_embdoc_end('=end', @f)
    assert_xhtml "<html><body>#{ @output }</body></html>"
  end

  def test_re_html_ize_embdoc_lines
    assert{ @rip.enline('foo') == 'foo' }
    assert{ @rip.enline('f&lt;code&gt;o&lt;/code&gt;o') == 'f<code>o</code>o' }
  end

  def test_on_embdoc_end
    assert_embdoc ['banner', 'yo', 'dude', "\r\n", 'what', 'up?']
    assert{ xpath :'p[ . = "yo dude"  ]' }
    denigh{ xpath :"p[ . = '\r\n'     ]" }
    assert{ xpath :'p[ . = "what up?" ]' }
    denigh{ @output =~ /=end/ }
    assert{ @output =~ /\<pre>/ }
    assert{ @rip.embdocs == [] }
  end

  def test_on_embdoc_end_with_unix_style_linefeeds
    assert_embdoc ['banner', 'yo', 'dude', "\n", 'what', 'up?']
    assert{ xpath :'p[ . = "yo dude"  ]' }
    denigh{ xpath :"p[ . = '\n'       ]" }
    assert{ xpath :p, :'.' => 'what up?' }
  end

  def test_embdoc_with_indented_samples
    assert_embdoc ['banner', 'yo', ' indented', 'dude']
    assert('TODO take out that little space'){ xpath :'p[ . = "yo " ]' }
    denigh{ xpath(:'p[ contains(., "indented") ]') }
    assert{ xpath :'p[ . = "dude" ]' }
  end

  def assert_rip(line)
    assert_xhtml RipDoc.compile_fragment(line)
  end
  
  def assert_rip_page(line)
    @sauce = RipDoc.compile(line)
    line = @sauce
    assert_xhtml line
    return line
  end

  def test_nested_string_mashers_form_well
    line = assert_rip('return "#{ format_snip(width, snip) } --> #{ format_value(width, value) }"')
    deny{ line =~ />>/ }
  end

  def test_no_ripping_between_nodoc_tags
    line = assert_rip( "x = 42\n" +
                       "#!nodoc!\n" +
                       "y = 43\n"
                      ) 
    assert_xhtml line
    assert{ xpath :span, :'.' => 'x'  }
    assert{ xpath :span, :'.' => '42' }
    denigh{ xpath :span, :'.' => '#!nodoc!' }
    denigh{ xpath :span, :'.' => 'y'  }
    denigh{ xpath :span, :'.' => '43' }
  end

  def test_nodoc_tags_end_at_doc_tags
    line = assert_rip( "#!nodoc!\n" +
                       "y = 43\n" +
                       "# miss me\n" +
                       "#!doc!\n" +
                       "x = 42\n"
                     )  #  TODO  interact correctly with =begin tags
    assert_xhtml line
    denigh{ xpath :span, :'.' => '#!nodoc!' }
    denigh{ xpath :span, :'.' => 'y'  }
    denigh{ xpath :span, :'.' => '43' }
    denigh{ xpath :span, :'.' => '# miss me' }
    assert{ xpath :span, :'.' => 'x'  }
    assert{ xpath :span, :'.' => '42' }
  end

  def test_rip_braces
    assert_rip 'hash = { :x => 42, 43 => 44 }'
    denigh{ xpath :'span[ contains( ., "{{" ) ]' }
    assert{ xpath :'span[ contains( ., "{"  ) ]' }
  end

  def test_comments_feed_lines
    lines = assert_rip('# comment
                        x = 42')
    assert{ lines =~ /comment<\/span>\n/ }
  end

# TODO  assert{ xpath() { nada } }  should not be a problem

#  TODO  add :verbose => option to xpath

  def test_put_every_thing_into_a_pre_block
    lines = assert_rip('x = 42')
    assert do
      xpath :div, :content do
        #puts(@xdoc.to_s) and
        xpath 'pre/span'
      end
    end
  end

  def style(kode)
    "@style = '#{RipDoc::STYLES[kode]}'"
  end
  
  def test_string_patterns
    assert_rip('foo "bar"')
    deny{ xpath :'span[ @class = "string" ]' }
return # TODO
    assert do # and 
      xpath :"span[ #{style(:string)} and . = 'bar'  ]" do
        xpath "span[ #{style(:string_delimiter)} and . = '\"' ]"
      end
    end
  end

  def test_string_mashers
    assert_rip 'x = "b#{ \'ar\' }"'

#  TODO  this really needs the silly args system?

    assert do # and 
      xpath :"span[ #{style(:string)} and contains(., 'b')  ]" do
        xpath(:"span[ #{style(:embexpr)} ]").text.index('#{') == 0
      end
    end
  end

  def toast_embdoc
    assert_rip "=begin\nbanner\nWe be\nembdoc\n=end"
puts @xdoc.to_s
    assert{ xpath(:"span[ #{style(:embdoc)} ]/div/p").text =~ /We be/m }
  end

  def test_color_backrefs
    assert_rip 'x = $1' #   and
    assert{ xpath :"span[ #{style(:backref)} and . = '$1' ]" }
  end

  def test_regexp_patterns
    assert_rip('foo /bar/')
    
    assert do
      xpath :"span[ #{style(:regexp)} and contains(., 'bar')  ]" do
        xpath "span[ #{style(:regexp_delimiter)} and contains(., '/') ]"
      end
    end
  end

#  TODO evaluate mashed strings
#  TODO  pick weird color for regices
#  TODO  when an assertion block throws an E, decorate it with the diagnostic text
#   TODO intersticial string mashers still don't color correctly
#   TODO make function names bigger
#  TODO  respect linefeeds in parsed source when reflecting

  def reveal(xhtml = @sauce || @output)
    filename = HomePath + 'doc/yo.html'
    File.write(filename, xhtml)  
    filename = filename.relative_path_from(Pathname.pwd)
    system "\"C:/Program Files/Mozilla Firefox/firefox.exe\" #{filename} &"
  end
  
end

