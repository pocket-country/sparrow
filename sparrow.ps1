# An SQL Lexer
# Basically we are building the scanner from Nystrom's Lox interpreter (see "Crafting Interpreters") ...
# ... translating Java -> PowerShell and Lox -> SQL.

#bring in file with Token class def & associated data structures
#Import-Module -Name ./Token.psm1
Using module ./Token.psm1

# input script name defaluts to test.sql
param ($script_name='./test.sql');

# set up a couple of log files for testing.  Better IO later
$null = new-item .\sparrowlogs\notscanned.log -force ;
$null = new-item .\sparrowlogs\tokens.log -force;

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

  #scanTokens method loops over source
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
      ',' {
        $this.addToken([TokenType]::COMMA); break;
      }
      '.' {
        $this.addToken([TokenType]::DOT); break;
      }
      '*' {
        $this.addToken([TokenType]::STAR); break;
      }
      '(' {
        $this.addToken([TokenType]::LPAREN); break;
      }
      ')' {
        $this.addToken([TokenType]::RPAREN); break;
      }
      ';' {
        $this.addToken([TokenType]::SEMI); break;
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
