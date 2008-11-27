#!/usr/bin/env ruby

require 'ripper'
require 'stringio'
require 'cgi'
require 'erb'
require 'optparse'
require 'pathname'


class RipDoc < Ripper::Filter
  HomePath = (Pathname.new(__FILE__).dirname + '..').expand_path

  def self.generate(filename, title)
    @sauce = compile_fragment(File.read(filename))
    @title = title
    erb = ERB.new((HomePath + 'lib/ripdoc.html.erb').read, nil, '>')
    return erb.result(binding())
  end

  attr_accessor :embdocs

  def deformat(line, f)
    if line =~ /^\s/
      f << "</p>\n" if @owed_p
      @owed_p = false
      f << line << "\n"
      return
    end
    
    f << '<p>' unless @owed_p
    @owed_p = true
    f << line
  end
  
  def on_embdoc_end(tok, f)
    f << span(:embdoc)
      f << '<p>'
      @owed_p = true
      previous = false
      
      @embdocs.each do |doc|
        if doc.strip == ''
          f << "</p>\n<p>"
          previous = false
        else
          f << ' ' if previous
          deformat(CGI.escapeHTML(doc), f)
          previous = true
        end
      end
      
      f << '</p>' if @owed_p
    f << '</span>'
    @embdocs = []
    on_kw tok, f, 'embdoc_end'
  end

  def on_embdoc_beg(tok, f)
    @embdocs = []
    on_kw tok, f, 'embdoc_beg'
  end

  def on_embdoc(tok, f)
    @embdocs << tok
    #on_kw tok, f, 'embdoc'
    return f
  end
  
  STYLES = {
    const:              "color: #FF4F00; font-weight: bolder;",
    backref:            "color: #f4f; font-weight: bolder;",
    comment:            "font-style: italic; color: gray;",
    embdoc:             "background-color: #FFe; font-family: Times; font-size: 133%;",
    embdoc_beg:         "display: none;",
    embdoc_end:         "display: none;",
    embexpr:            "background-color: #ccc;",
    embexpr_delimiter:  "background-color: #aaa;",
    gvar:               "color: #8f5902; font-weight: bolder;",
    ivar:               "color: #240;",
    int:                "color: #336600; font-weight: bolder;",
    operator:           "font-weight: bolder; font-size: 120%;",
    kw:            "color: purple;",
    regexp_delimiter:   "background-color: #faf;",
    regexp:             "background-color: #fcf;",
    string:             "background-color: #dfc;",
    string_delimiter:   "background-color: #cfa;",
    symbol:             "color: #066;",
  }

  def span(kode)
    if STYLES[kode.to_sym]
      # class="#{kode}" 
      return %Q[<span style="#{STYLES[kode.to_sym]}">]
    else
      return '<span>'
    end
  end
  
  def spanit(kode, f, tok)
    @spans_owed += 1
    f << span(kode) << CGI.escapeHTML(tok)
  end

  def on_kw(tok, f, klass = 'kw')
    f << span(klass) << CGI.escapeHTML(tok)
    f << '</span>'
  end

  def on_comment(tok, f)
    spanit :comment, f, tok.rstrip
    on_nl nil, f
  end

# TODO linefeeds inside %w() and possibly ''
#  TODO colorize :"" and :"#{}" correctly

  def on_default(event, tok, f)
    if @symbol_begun
      @symbol_begun = false
      f << %Q[#{span(:symbol)}#{CGI.escapeHTML(tok)}</span>]
    elsif tok =~ /^[[:punct:]]+$/
      f << %Q[#{span(:operator)}#{CGI.escapeHTML(tok)}</span>]
    else
       #p tok, event
      on_kw tok, f, event.to_s.sub(/^on_/, '')
    end
    
    return f
  end

  def finish_one_span(f)
    if @spans_owed > 0
      f << '</span>' 
      @spans_owed -= 1
    end
  end

  def on_tstring_beg(tok, f)
    @spans_owed += 1
    f << span(:string)
    f << %Q[#{span(:string_delimiter)}#{CGI.escapeHTML(tok)}</span>]
  end

  def on_tstring_end(tok, f)
    f << %Q[#{span(:string_delimiter)}#{CGI.escapeHTML(tok)}</span>]
    finish_one_span(f)
    return f
  end

  def on_regexp_beg(tok, f)
    @spans_owed += 1
    f << span(:regexp)
    f << %Q[#{span(:regexp_delimiter)}#{CGI.escapeHTML(tok)}</span>]
  end

  def on_regexp_end(tok, f)
    f << %Q[#{span(:regexp_delimiter)}#{CGI.escapeHTML(tok)}</span>]
    finish_one_span(f)
    return f
  end

  def on_embexpr_beg(tok, f)
    spanit :embexpr, f, tok
    return f
  end
  
  def on_ignored_nl(tok, f)
    on_nl nil, f
  end

  def on_nl(tok, f)
    finish_any_spans(f)  # TODO  this can't be needed...
    f << "\n"
  end

  def on_lbrace(tok, f)
#p [tok, 'onlbrace']
    spanit '', f, '' # tok  CONSIDER  wonder who is actually emitting the { ??
    f << tok
  end
  
  def on_rbrace(tok, f)
    f << tok
    finish_one_span(f)  #  TODO  these things might wrap lines!
    return f
  end

  def on_symbeg(tok, f)
    on_default(:on_symbeg, tok, f)
    @symbol_begun = true
    return f
  end

  def finish_any_spans(f)
    @spans_owed.times{ finish_one_span(f) } 
  end

#  TODO  syntax hilite the inner language of regices? how about XPathics?

  def on_tstring_content(tok, f)
    f << CGI.escapeHTML(tok)
  end

  def on_ivar(tok, f)
    f << %Q[#{span(:ivar)}#{CGI.escapeHTML(tok)}</span>]
  end

  attr_accessor :spans_owed

  def parse(buf, f)
    @spans_owed = 0
    @symbol_begun = false
    super(buf)
    #finish_any_spans(f)
  end

DOCTYPE = '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" 
              "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">' +
              "\n"

  def RipDoc.compile(f)
    buf = StringIO.new
    parser = RipDoc.new(f)
    parser.parse(buf, f)
    result = buf.string
    parser.spans_owed.times{ result += '</span>' }

    return DOCTYPE +
            '<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en" dir="ltr"
            ><head>' + 
           '</head><body><div id="content"><pre>' + result + 
           '</pre></div></body></html>'
  end

  def RipDoc.compile_fragment(f)
    buf = StringIO.new
    parser = RipDoc.new(f)
    parser.parse(buf, f)
    result = buf.string
    parser.spans_owed.times{ result += '</span>' }

    return '<div id="content"><pre>' + result + '</pre></div>'
  end

end

if $0 == __FILE__
  system 'ruby ../test/ripdoc_test.rb'
#  main
end

#~ :on_ident
#~ :on_tstring_content
#~ :on_const
#~ :on_semicolon
#~ :on_op
#~ :on_int
#~ :on_comma
#~ :on_lparen
#~ :on_rparen
#~ :on_backref
#~ :on_period
#~ :on_lbracket
#~ :on_rbracket
#~ :on_rbrace
#~ :on_qwords_beg
#~ :on_words_sep

def main
  encoding = 'us-ascii'
  css = nil
  print_line_number = false
  parser = OptionParser.new
  parser.banner = "Usage: #{File.basename($0)} [-l] [<file>...]"
  parser.on('--encoding=NAME', 'Character encoding [us-ascii].') {|name|
    encoding = name
  }
  parser.on('--css=URL', 'Set a link to CSS.') {|url|
    css = url
  }
  parser.on('-l', '--line-number', 'Show line number.') {
    print_line_number = true
  }
  parser.on('--help', 'Prints this message and quit.') {
    puts parser.help
    exit 0
  }
  begin
    parser.parse!
  rescue OptionParser::ParseError => err
    $stderr.puts err
    $stderr.puts parser.help
    exit 1
  end
  puts RipDoc(ARGF, encoding, css, print_line_number)
end

class ERB
  attr_accessor :lineno

  remove_method :result
  def result(b)
    eval(@src, b, (@filename || '(erb)'), (@lineno || 1))
  end
end

def RipDoc(f, encoding, css, print_line_number)
  erb = ERB.new(TEMPLATE, nil, '>')
  erb.filename = __FILE__
  erb.lineno = TEMPLATE_LINE
  erb.result(binding())
end

