# Minnow is a pre-processor for T-SQL code.
# Wanted to:
# - be able to handle nested block comments (PITA, see tail.ps1)
# - create a 'minified' sql file w/ dup whitespace removed, all ws -> blank, comments removed
# - create an input file for sparrow so I don't have to embed all of the above into my scanner
#
# Note  that the third item above will require creating a data format to pass along position info
# for the scanner along with txt so can report errors  correctly.  Here we are trading the reduction of
# complexity in terms of not having the scanner deal with comment parsing for increased complexity
# of tracking position for error messages.
#
# Also, always wanted to build a DFA/state machine for fun.  Old Skool Cook.  #
# Choose to build the state transition table "in code" vs
# more general purpose  method (see a useful set of blog posts at //)
# Can I bang this out in an afternoon?  Have a lot of the thinking/design done ...

# We are in a scripting language have to declare functions before use!  Just like the olden days.

# class - in the Pascal sense, a data record, to hold an 'extended character - our IR that holds position info as well as character
class EC {
    [char] $byte;
    [int] $line;
    [int] $ofst;
    #constructor
    EC([char] $c, [int] $l, [int] $o) {
        $this.byte = $c;
        $this.line = $l;
        $this.ofst = $o;
    }
}
# holds internal representation we are building, an array of extended character objects.
$eChars = New-Object -TypeName "System.Collections.ArrayList";

# class to encapsulate the input text file/string/buffer ... like an actual class with methods.
# I wanted to write a scrappy little script without this stuff, but ...
# Wasted a full day of my life trying to find a weird bug (actually used debugger!).  Return from write, value in 
# global $Current reverts to 0 on first iteration works fine on subsequent iterations.
# Got lost in PS's weired scripty scope rules, returns, lack of type declarations at 'script' level
# So am hoping more modern encapsulation/data structure will fix the problem.  Still no idea what bug is
# Am gonna pretend I'm writing Java/C++/C#

class InputBuffer {
    [string] $src;
    [int] $current;
    [int] $lineNum;
    [int] $lineStart;

    # Constructor, load text into string and initialze counters
    InputBuffer ([string] $inputfile) {
        $this.src = Get-Content $inputfile -raw;;
        $this.current = 0;
        $this.lineNum= 1;
        $this.lineStart = 0;
    }
    [bool] IsAtEnd() { #true if end of input text
        return ($this.current -ge ($this.src.length))
    }
    [string] Peek($n) { # look at current (or subsequent) charater in input buffer without advancing pointer
        $tc = $this.src[$this.current + $n];
        #if ($script:doggit) {add-content $script:mlog " Peeking at $this.current + $n : $tc"}
        return $tc;
    }
    # could put in handling for skipping/retreiving past end of output buffer.  Do i need too?
    [void] Skip($n) { #advance pointer without returning character 
        if ($this.src[$this.current] -eq "`n") { $this.lineNum++; $this.LineStart = $this.current; }
        $this.current = $this.current + $n;
    }
    [string] GetChr() { # return current character, advance pointer
        $tc = $this.src[$this.current]; #maybe could do all this in return stmt but they are twichy in PS
        if ($this.src[$this.current] -eq "`n") { $this.lineNum++; $this.LineStart = $this.current; }
        $this.current++;
        return $tc;
    }
    # for future development, if we want to pull comment txt
    [void] Mark() {Write-Host "Method InputBuffer.Mark() not implemented."}
    [string] Lexeme() {Write-Host "Method InputBuffer.Lexeme not implemented"; return $Null}
}
function Write($n){ # eat current character(s), make an extended chr object.
    for ($i = 0; $i -lt $n; $i++) {
        ### TODO this is wrong if the prior character was a newline! b/c things have been incremented
        $extChr = [EC]::new($sqlIn.getChr(), $sqlIn.lineNum, ($sqlIn.current - $sqlIn.LineStart));
        [void] $eChars.add($extChr);
        # how to decouple and not have globals?
        # so I guess we call the function 'transfer' and pass in both the input and output object?
    }
}
function WriteBlank() { #for use in  whitespace processing, write a space
    $eChr = [EC]::new(" ", $sqlIn.lineNum, ($sqlIn.current - $sqlIn.LineStart)); # bad bad bad should pass in object
    [void] $eChars.add($eChr);
}
# logging
function LogAction( $action) {
    if ($doggit) {add-content $mlog "--> $action"}
}
function LogState() {
    if ($doggit) {add-content $mlog "In state $state with:$c"}
}
# comment "stack" is just a number for now.  Later, maybe store actual text in an actual stack.
# so we will make a class, but it is a silly one.
Class CS {
    [int] $CommentStack;

    CS() {$this.CommentStack = 0}

    [void] Push() {$this.CommentStack++}
    [void] Pop()  {$this.CommentStack--}
    [bool] InAComment() { return $this.CommentStack -Gt 0}
}
function PushComment() {
    $script:commentStack++;
}
function PopComment() {
    $script:commentStack--;
}
#set up log for testing state dynamics
$doggit = $true;
if ($doggit) {
    $mlog = "minnow.log";
    $null = new-item $mlog -force ;
}
# global tracking  variables.
$commentStack = [CS]::new();  #Initialize the comment stack. How deep are we in nested comments?

# Read SQL into a new input buffere object
# int main(int argc, char *argv[]) { }
if ($args) {$scrFileName = $args} else {$scrFileName = "./testMinnow.sql"}
$sqlIn = [InputBuffer]::new($ScrFileName);

# statistics - counts of comments, blank lines, code lines, etc

#initialize state loop
$state = "beg";     # everyone just numbers these, but then ... which is which?
                    # I'm gonna use a 3 chr mnemonic
$iter = 0; # for setting up a 'safety' during debugging
$limit = 100; #max iterations
if ($limit -gt 0) {Write-Host "Minnow in a fishbowl: $limit"}

# first pass write everything out for clarity.  Then refactor into functions for efficiency.
Write-Host Processing

# the state machine loop:
while (-not $sqlIn.IsAtEnd()) {
    $iter++
    if ($iter -gt $limit) {Write-Host "Hit The Wall!"; Break;} 
    else {if ($doggit) {Write-Host "Iteration ($iter)"}}

    Switch ($state) {
        'beg' { #1 'home' or beginning
            $c = $sqlIn.Peek(0);
            LogState;
            switch ($c) {
                '-'  {$state = 'ds1'; break;}
                '/'  {$state = 'bc1'; break;}
                ' '  {$state = 'ws1'; LogAction("write a blank"); WriteBlank; break;}
                "`t" {$state = 'ws1'; LogAction("write a blank"); WriteBlank; break;}
                "`n" {$state = 'ws1'; LogAction("write a blank for newline"); WriteBlank; break;}
                default { $state = 'beg';
                        LogAction("process a regular charcter");
                        Write(1);
                        break;}
            }
            break;
        }
        'ds1' { #2 saw first dash of a double dash, look for second
            $c = $sqlIn.Peek(1);
            LogState;
            switch ($c) {
                '-'  {$state = 'ds2';
                        $sqlIn.Skip(2);         # second of two dashes, jump  over 'em both
                        $commentStack.Push();   # and we are in a comment, boys
                        break;}
                default {$state = 'beg';
                        Write(2); #false alarm.  Write this character, and the prior dash which as it turns out did not signify  a comment.
                        break;}
            }
            break;
        }
        'ds2' { #3 here if saw second dash of a double dash comment - so in a comment.  Chew it up till newline.
            $c = $sqlIn.Peek(0);
            LogState;
            switch ($c) {
                "`n" {$state = 'beg';
                    LogAction("end double dash comment");
                    $sqlIn.Skip(1);
                    $commentStack.Pop();
                    break;}
                default {$state = 'ds2';
                    LogAction("skip over character inside double dash comment");
                    $sqlIn.Skip(1)
                    break;}
            }
            break;
        }
        'bc1' { #4 peeked at a slash might begin a block comment
            $c = $sqlIn.Peek(1);
            LogState;
            switch ($c) {
                '*'  {$state = 'bc2';  # Yes, block comment jump over slash star, push comment stack
                        LogAction("Enter block comment");
                        $sqlIn.skip(2);
                        $commentStack.Push();
                        break;}  
                default {$state = 'beg';  # Nope, that was just a slash
                        LogAction("process a regular charcter (false alarm)");
                        Write(2); # So write this character, and the prior *.
                    break;}
            }
            break;
        }
        'bc2' { #5 yep, saw a slash star followng def are in a new block comment. Top level or nested, chew through it.  
            $c = $sqlIn.Peek(0);
            LogState;
            switch ($c) {
                "*" {$state = 'bcq'; # might be end of block comment, delay write/skip and look at next byte; 
                        LogAction("might be end");
                        break;}
                default {$state = 'bc2';
                        LogAction("skip over character inside block comment"); 
                        $sqlIn.Skip(1) #recall skip handles newline;
                        break;}
            }
            break;
        }
        'bcq' { #6 saw a star inside a block comment.  Is this the end?
            $c = $sqlIn.Peek(1);
            LogState;
            switch ($c) {
                "/" {$state = 'bce'
                        LogAction("End block comment"); # Yes!  But still have a decision to make 
                        $commentStack.Pop();
                        break;}
                default {$state = 'beg';
                    LogAction("Skip over character inside block comment");
                    sqlIn.skip(2);   #skip over the star (false alarm) and slash that form delimiter;
                    break;
                }
            }
            break;
        }
        'bce' { #7 just ended a block comment.  But was it nested?  Don't look at the input buffer!
                # Note if we didn't have to check the comment stack here
                # we might as well usee tail.ps1/regex based minifier.
                # This here is the crux of handling nested comments.
            if ($commentStack.InAComment()) { # I wrote this whole damm program just to get to this if!
                $sqlIn.skip(2);  # skip over star slash that ended comment, still in a nested comment.
                $state = 'bc2'
            } else {
                $sqlIn.skip(2) # skip over star slash that ended comment, not in a nested comment
                $state = 'beg';
            }
        }
        'ws1' { # 8: keep skipping consecutive white space
            $c = $sqlIn.Peek(0);
            LogState;
            switch ($c) {
                '-'  {$state = 'ds1'; break;}
                " "  {$state = 'ws1'; $sqlIn.Skip(1); break;}
                "`t" {$state = 'ws1'; $sqlIn.Skip(1); break;}
                "`n" {$state = 'ws1'; $sqlIn.Skip(1); break;}
                default {$state = 'beg';
                    LogAction("leaving white space, process regular character");
                    Write(1);
                    break}
            }
            break;
        }
    } # end state switch
} # end main while loop

# if state = final then OK else error
# am currently not dealing with this as basically any text is a legal string
# we are just pulling out chunks of it.

#any post processing
Write-Host "Generating Output"
# TODO need to set up flags or something to control input and output file names and set these output booleans

$console = $true;
if ($console) { #dump value to default output
    $eChars;
}

$json = $false;
if ($json) { # write  in json format.  Warning, this the file probably by a factor of 10
    $outfile = "./minnow.json"
    ConvertTo-Json -EnumsAsStrings -depth 3 -InputObject ($eChars) | Out-File "./minnow.json"
}

$minify = $false;
if ($minify) { #output as minified text.  This looses origional position info but preserves SQL (with \s* -> ' ' and comments removed)
    $outfile = "./minnow.min";
    $stringBuilder = [System.Text.StringBuilder]::new()
    foreach ( $ec in $eChars) { 
        #$ec.byte;
        [void] $stringBuilder.Append($ec.byte) 
    }
    $null = new-item $outfile -force ;
    add-content $outfile $stringBuilder.ToString() 
}
# ### #