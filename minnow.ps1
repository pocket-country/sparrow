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
    [int] $atline;
    [int] $atoffset;
    #constructor
    EC([char] $c, [int] $l, [int] $o) {
        $this.byte = $c;
        $this.atline = $l;
        $this.atoffset = $o;
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
        $this.current++
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
$commentStack = 0;          #actually a counter, how deep are we in nested comments.

# Read SQL into a new input buffere object
# int main(int argc, char *argv[]) { }
if ($args) {$scrFileName = $args} else {$scrFileName = "./testMinnow.sql"}
$sqlIn = [InputBuffer]::new($ScrFileName);

# statistics - counts of comments, blank lines, code lines, etc

#initialize state loop
$state = "beg";     # everyone just numbers these, but then ... which is which?
                    # I'm gonna use a 3 chr mnemonic
$iter = 0; # for setting up a 'safety' during debugging

# first pass write everything out for clarity.  Then refactor into functions for efficiency.
Write-Host Start processing

# the state machine loop:
while (-not $sqlIn.IsAtEnd()) {
    $iter++
    if ($iter -gt 100) {Write-Host "Hit The Wall!"; Break;} 
    else {if ($doggit) {Write-Host "Iteration ($iter)"}}

    Switch ($state) {
        'beg' { #1 'home' or beginning
            $c = $sqlIn.Peek(0);
            LogState;
            switch ($c) {
                '-'  {$state = 'ds1'; break;}
                # not wired up at the moment '/'  {$state = 'bc1'; break;}
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
                        $sqlIn.Skip(2);  # second of two dashes, jump  over 'em both
                        PushComment;         # and we are in a comment, boys
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
                "`n"  {$state = 'beg';
                    LogAction("end double dash comment");
                    $sqlIn.Skip(1);
                    PopComment;
                    break;}
                default {$state = 'ds2';
                    LogAction("skip over character inside double dash comment");
                    $sqlIn.Skip(1)
                    break;}
            }
            break;
        }
        'bc1' { #4
            $c = $sqlIn.Peek(0);
            LogState;
            switch ($c){
                '*'  {$state = 'bcc'; LogAction("start block commeent"); break}
                default {$state = 'beg'; LogAction("process a regular charcter") break;}
            }
            break;
        }
        'bcc' { #5
            $c = $sqlIn.Peek(0);
            LogState;
            break;
        }
        'bcq' { #6
            $c = $sqlIn.Peek(0);
            LogState;
            break;
        }
        'bce' { #7
            $c = $sqlIn.Peek(0);
            LogState;
            break;
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

#if state = final then OK else error

#any post processing
Write-Host "post processng"
$eChars;
ConvertTo-Json -EnumsAsStrings -depth 10 -InputObject ($eChars) | Out-File "./test.json"
# ### #
