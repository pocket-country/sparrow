# An SQL Lexer
# Basically we are building the scanner from Nystrom's Lox interpreter (see "Crafting Interpreters") ...
# ... translating Java -> PowerShell and Lox -> SQL.

#bring in file with Token class def & associated data structures
#Import-Module -Name ./Token.psm1
Using module ./Token.psm1

# input script name defaluts to test.sql
param ($script_name='./test.sql');

# set log file to dump stuff we can't process.  Better error handling later.
$null = new-item .\sparrowlogs\notscanned.log -force ;

class scanner {
  [String] $source;
  [int] $start;
  [int] $current;
  [int] $line;
  [System.Collections.ArrayList] $tokens;

  # constructor stores source string & sets up empty list of tokens
  scanner([string]$src) {
    $this.source = $src;
    $this.tokens = New-Object -TypeName "System.Collections.ArrayList";
    $this.start = 0;
    $this.current = 0;
    $this.line = 1;
  }

  #scanTokens method loops over source & adds EOF at end.
  [void] scanTokens() {
    While (-not $this.isAtEnd()) {
      $this.start = $this.current;
      $this.scanToken();
    }
    $this.addToken([TokenType]::EOF);
  }

  # this is the big workhorse - pull out one token
  [void] scanToken() {
    $c = $this.advance();
    switch ($c) {
      # single character tokens mostly operators & punctuation
      ',' {$this.addToken([TokenType]::COMMA); break;}
      '.' {$this.addToken([TokenType]::DOT); break;}
      '*' {$this.addToken([TokenType]::STAR); break;}
      '+' {$this.addToken([TokenType]::PLUS); break;}
      '(' {$this.addToken([TokenType]::LPAREN); break;}
      ')' {$this.addToken([TokenType]::RPAREN); break;}
      ';' {$this.addToken([TokenType]::SEMI); break;}
      # comments
      # '-' is different as can start a comment
      '-' {
        if ($this.match('-')) { #if we see a second - ignore till end of line
          while($this.peek() -ne '`n' -and (-not $this.isAtEnd)) {$this.advance()}
        } else {
          $this.addToken([TokenType]::MINUS);
        }
        break;
      }
      # code/algo for handling /* */ comments adapted from Chelsea Troy's Lox implemetation
      #(https://github.com/chelseatroy/craftinginterpreters/blob/block-comment-solution/java/com/craftinginterpreters/lox/Scanner.java)
      # I don't think this handles nested comments.  Also would be difficult to capture comment text
      '/' {
        if ($this.match('*')) { #then we are in a comment, skip characters till we see potentil end comment
          while ($this.peek() -ne '*' -and (-not $this.isAtEnd())) { $this.advance();}
        } else {
        $this.addToken([TokenType]::SLASH);
        }
        break;
      }
      # asterisk denotes multiplication, but also ends block comments
      '*' {
        if ($this.match('/')) { # finish advancing past comment - though I don't get why a while!?!?!
          while ($this.peek() -ne '`n' -and ( -not $this.isAtEnd())) { $this.advance() };
        } else {
          $this.addToken([TokenType]::STAR);
        }
        break;
      }
      # double character tokens
      '!' {
        if($this.match('=')) {
          $this.addToken([TokenType]::BANG_EQUAL)
        } else {
          $this.addToken([TokenType]::BANG)
        }
        break;
      }
      '=' {
        if($this.match('=')) {
          $this.addToken([TokenType]::EQUAL_EQUAL)
        } else {
          $this.addToken([TokenType]::EQUAL)
        }
        break;
      }
      '>' {
        if($this.match('=')) {
          $this.addToken([TokenType]::LESS_EQUAL)
        } else {
          $this.addToken([TokenType]::LESS)
        }
        break;
      }
      '<' {
        if($this.match('=')) {
          $this.addToken([TokenType]::GREATER_EQUAL)
        } else {
          $this.addToken([TokenType]::GREATER)
        }
        break;
      }
      # whitespace - do nothing with it
      ' '   { break; }
      "`t"  { break; }
      "`r"  { break; }
      # watch for different line endings in windows land
      "`n" { $this.line = $this.line + 1; break }
      #sql strings start with a single quote
      "'" { $this.string(); break; }
      # fall through, not a fixed single or multi char token
      default {
        if ( $this.isAlpha($c)) {
          $this.identifier();
        } #TODO add numeric literals - storing as strings (that object field issue)
          #these are processed like strings, but start with a digit or - and contain
          # ... digits, commans, decimal pt.
          #TODO add SQL quoting for weird chars in col/table names [] and ""
          # ... these are processed like strings, with delimiters, but write an 
          # ... identifier token.  Do we need to distinguish the two types of identifiers?
          # ... like an IDENTIFIER token and a QIDENTIFIER token?
        else {
          add-content .\sparrowlogs\notscanned.log "Not Scanned: $c at line $( $this.line ), byte position $( $this.current - 1 )."
        }
      }
    }
  }

  # want two add token signatures - one for 'fixed' tokens and one for literals
  # in java, the simple one calls the complex one with a null, and uses a generic object to store value.  
  #Don't know if we can do that here, nor do I know how nulls work so repeat some code.
  [void] addToken([TokenType] $type) {
    $text = $this.source.substring($this.start, $this.current);
    $token = [token]::new($type, $text, "--", $this.start - 1);
    $this.tokens.add($token);
  }
  [void] addToken([TokenType] $type, [string] $literal) {
    $text = $this.source.substring($this.start, $this.current);
    $token = [token]::new($type, $text, $literal, $this.start - 1);
    $this.tokens.add($token)
  }
  #process identifiers
  [void] identifier() {
    while ($this.isAlphaNumeric($this.peek())) {$this.advance();}
    #lexeme stored in token is identifier name.
    #TODO for keywords add dictionary
    $this.addToken([TokenType]::IDENTIFIER);
  }
  #process string literals.  This allows any character inc. newline in string which may not be valid SQL
  #note also not handling any excaping or string interpolation
  [void] string() {
    while ($this.peek() -ne "'" -and $this.isAtEnd()) {
      if($this.peek() -eq "`n") {$this.line = $this.line + 1;}
      $this.advance();
    }
    if ($this.isAtEnd()) { #need to figure out error handling
      Write-Host Unterminated string;  #and halt!
    }
    #move past closing quote
    $this.advance();
    #trim the quotes and add a token with the string value
    [string] $value = $this.source.Substring($this.start+1, $this.current -1)
    $token.addToken([TokenType::String])
  }
  # all the little helpers - first test functions, then character handling (advance, match peek);
  [bool] isAtEnd() {
    Return $this.current -ge $this.source.length;
  }
  [bool] isAlpha([char] $c) {
    return ($c -ge 'a' -and $c -le 'z') -or ($c -ge 'a' -and $c -le 'z');
  }
  [bool] isDigit([char] $c) {
    return ($c -ge '0' -and $c -le '9');
  }
  [bool] isAlphaNumeric([char] $c) {
    return ( $this.isAlpha($c) -or $this.isDigit($c));
  }
  [char] advance() {
    $tc = $this.source[$this.current];
    $this.current = $this.current + 1;
    return $tc;
  }
  [char] peek() {
    if ($this.isAtEnd()) {return "`0"}
    return $this.source[$this.current];
  }
  [bool] match([char] $expected ) {
    if ($this.isAtEnd()) {return $false}
    if ($this.source[$this.current] -ne $expected) {return $false}

    $this.current = $this.current + 1;
    return $true;
  }
}

#Scanner class is defined.  Here is the main loop.  Get the source code,
# instantiate a scanner class, and go for it
#This is the moral equivalent of Run() in Nystrom's book
$src = Get-Content $script_name -raw;

$scanner = [scanner]::new($src);

$scanner.scanTokens();

$tokens = $scanner.tokens;

#Write-Host Done Scanning. Results are:
#ForEach ( $t in $tokens ) {
# Write-Host $t.pp();
#}
#ConvertTo-Xml -As "string" -InputObject ($tokens) -Depth 3 | Out-File "./test.xml"
ConvertTo-Json -EnumsAsStrings -depth 3 -InputObject ($tokens) | Out-File "./test.json"
#$tokens | Format-Xml | Out-File "./test.xml"
