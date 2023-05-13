# first try at an SQL Parser
# Basically we are building Nystrom's Lox Java intrepretre (see "Crafting Interpreters") ...
# ... translating Java -> PowerShell and Lox -> SQL.
param ($script_name='./test.sql');
$null = new-item .\sparrowlogs\notscanned.log -force ;
$null = new-item .\sparrowlogs\tokens.log -force;

#this is going to be a potentially enormous list so wana figure out how to put soruce elsewhere
enum Token {COMMA; DOT; STAR; LPAREN;  RPAREN; SEMI; STRING; IDENTIFIER; EOF}

# not java so don't put in a seperate file?  Have to define before use?
class scanner {
  [String] $source;
  [int] $start;
  [int] $current;
  [int] $line;
  [System.Collections.Generic.List[Token]] $tokens;

  #::new()

  # constructor stores source string
  scanner([string]$src) {
    $this.source = $src;
    $this.tokens = [System.Collections.Generic.List[Token]]::new();
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
    $this.tokens.add('EOF');
  }

  # this is the big workhorse - pull out one token
  [void] scanToken() {
    $c = $this.advance();
    switch ($c) {
      ',' {
        $this.addToken([token]::COMMA); break;
      }
      '.' {
        $this.addToken([token]::DOT); break;
      }
      '*' {
        $this.addToken([token]::STAR); break;
      }
      '(' {
        $this.addToken([token]::LPAREN); break;
      }
      ')' {
        $this.addToken([token]::RPAREN); break;
      }
      ';' {
        $this.addToken([token]::SEMI); break;
      }
      # whitespace
      ' ' {
        break;
      }
      "`t" {
        break;
      }
      "`r" {
        break;
      }
      # watch for different line endings in windows land
      "`n" {
        $this.line = $this.line + 1; break
      }
      #character strings (will test for keywords with a dictionary lookup.  Not going to handle " or [ quoting for now ...
      #maybe just scan "" [] as tokens?  Maybe as string start, with a different string() function?  Maybe let strings contain anything?
      #"'" { $this.string(); break;}  TO ADD THIS I NEED TOKEN TO BE AN OBJECT (so can include value!)

      default {
        if ( $this.isAlpha($c)) {
          $this.identifier();
        }
        else {
          add-content .\sparrowlogs\notscanned.log "Invalid Character: $c at line $( $this.line ), byte position $( $this.current - 1 )."
        }
      }
    }
  }
  [void] addToken([token] $type) {
    $this.tokens.add($type);
    add-content .\sparrowlogs\tokens.log "adding $type found at line $($this.line) byte position $($this.start -1 )"
  }
  [void] identifier() {
    while ($this.isAlphaNumeric($this.peek())) {$this.advance();}
    #TODO need to mod token to have a lexeme - this will be the identifers name
    #TODO for keywords add dictionary
    $this.addToken([token]::IDENTIFIER);
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

Write-Host Done Scanning. Results are:
ForEach ( $t in $tokens ) {
  Write-Host $t;
}
